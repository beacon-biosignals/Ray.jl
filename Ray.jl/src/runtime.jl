const GLOBAL_STATE_ACCESSOR = Ref{rayjll.GlobalStateAccessor}()

function init()
    # XXX: this is at best EXREMELY IMPERFECT check.  we should do something
    # more like what hte python Worker class does, getting node ID at
    # initialization and using that as a proxy for whether it's connected or not
    #
    # https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/python/ray/_private/worker.py#L421
    if isassigned(FUNCTION_MANAGER)
        @warn "Ray already initialized, skipping..."
        return nothing
    end

    # TODO: use something like the java config bootstrap address (?) to get this
    # information instead of parsing logs?  I can't quite tell where it's coming
    # from (set from a `ray.address` config option):
    # https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/java/runtime/src/main/java/io/ray/runtime/config/RayConfig.java#L165-L171
    args = parse_ray_args_from_raylet_out()
    gcs_address = args[3]

    opts = rayjll.GcsClientOptions(gcs_address)
    GLOBAL_STATE_ACCESSOR[] = rayjll.GlobalStateAccessor(opts)
    rayjll.Connect(GLOBAL_STATE_ACCESSOR[]) ||
        error("Failed to connect to Ray GCS at $(gcs_address)")
    atexit(() -> rayjll.Disconnect(GLOBAL_STATE_ACCESSOR[]))

    job_id = rayjll.GetNextJobID(GLOBAL_STATE_ACCESSOR[])

    initialize_coreworker_driver(args..., job_id)
    atexit(rayjll.shutdown_coreworker)

    _init_global_function_manager(gcs_address)

    return nothing
end

# this could go in JLL but if/when global worker is hosted here it's better to
# keep it local
get_current_job_id() = rayjll.ToInt(rayjll.GetCurrentJobId())

function parse_ray_args_from_raylet_out()
    #=
    "Starting agent process with command: ... \
    --node-ip-address=127.0.0.1 --metrics-export-port=60404 --dashboard-agent-port=60493 \
    --listen-port=52365 --node-manager-port=58888 \
    --object-store-name=/tmp/ray/session_2023-08-14_14-54-36_055139_41385/sockets/plasma_store \
    --raylet-name=/tmp/ray/session_2023-08-14_14-54-36_055139_41385/sockets/raylet \
    --temp-dir=/tmp/ray --session-dir=/tmp/ray/session_2023-08-14_14-54-36_055139_41385 \
    --runtime-env-dir=/tmp/ray/session_2023-08-14_14-54-36_055139_41385/runtime_resources \
    --log-dir=/tmp/ray/session_2023-08-14_14-54-36_055139_41385/logs \
    --logging-rotate-bytes=536870912 --logging-rotate-backup-count=5 \
    --session-name=session_2023-08-14_14-54-36_055139_41385 \
    --gcs-address=127.0.0.1:6379 --minimal --agent-id 470211272"
    =#
    line = open("/tmp/ray/session_latest/logs/raylet.out") do io
        while !eof(io)
            line = readline(io)
            if contains(line, "Starting agent process")
                return line
            end
        end
    end

    # --raylet-name=/tmp/ray/session_2023-08-14_18-52-23_003681_54068/sockets/raylet
    raylet_match = match(r"raylet-name=((\/[a-z,0-9,_,-]+)+)", line)
    raylet = raylet_match !== nothing ? String(raylet_match[1]) : error("Unable to find Raylet socket")

    # --object-store-name=/tmp/ray/session_2023-08-14_18-52-23_003681_54068/sockets/plasma_store
    store_match = match(r"object-store-name=((\/[a-z,0-9,_,-]+)+)", line)
    store = store_match !== nothing ? String(store_match[1]) : error("Unable to find Object Store socket")

    # --gcs-address=127.0.0.1:6379
    gcs_match = match(r"gcs-address=(([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5})", line)
    gcs_address = gcs_match !== nothing ? String(gcs_match[1]) : error("Unable to find GCS address")

    # --node-ip-address=127.0.0.1
    node_ip_match = match(r"node-ip-address=(([0-9]{1,3}\.){3}[0-9]{1,3})", line)
    node_ip = node_ip_match !== nothing ? String(node_ip_match[1]) : error("Unable to find Node IP address")

    # --node-manager-port=63639
    port_match = match(r"node-manager-port=([0-9]{1,5})", line)
    node_port = port_match !== nothing ? parse(Int, port_match[1]) : error("Unable to find Node Manager port")

    # TODO: downgrade to debug
    @info "Raylet socket: $raylet, Object store: $store, Node IP: $node_ip, Node port: $node_port, GCS Address: $gcs_address"

    return (raylet, store, gcs_address, node_ip, node_port)
end

initialize_coreworker_driver(args...) = rayjll.initialize_coreworker_driver(args...)

project_dir() = dirname(Pkg.project().path)

function submit_task(f::Function, args...)
    export_function!(FUNCTION_MANAGER[], f, get_current_job_id())
    fd = function_descriptor(f)
    # TODO: write generic Ray.put and Ray.get functions and abstract over this buffer stuff
    object_ids = map(collect(args)) do arg
        io=IOBuffer()
        serialize(io, arg)
        buffer_ptr = Ptr{Nothing}(pointer(io.data))
        buffer_size = sizeof(io.data)
        return rayjll.put(rayjll.LocalMemoryBuffer(buffer_ptr, buffer_size, true))
    end
    return GC.@preserve args rayjll._submit_task(project_dir(), fd, object_ids)
end

function task_executor(ray_function, ray_objects)
    @info "task_executor: called for JobID $(rayjll.GetCurrentJobId())"
    fd = rayjll.GetFunctionDescriptor(ray_function)
    # TODO: may need to wait for function here...
    @debug "task_executor: importing function" fd
    func = import_function!(FUNCTION_MANAGER[],
                            rayjll.unwrap_function_descriptor(fd),
                            get_current_job_id())
    # for some reason, `eval` gets shadowed by the Core (1-arg only) version
    # func = Base.eval(@__MODULE__, Meta.parse(rayjll.CallString(fd)))
    # TODO: write generic Ray.put and Ray.get functions and abstract over this buffer stuff
    args = map(ray_objects) do ray_obj
        v = take!(rayjll.GetData(ray_obj[]))
        io = IOBuffer(v)
        return deserialize(io)
    end
    arg_string = join(string.("::", typeof.(args)), ", ")
    @info "Calling $func($arg_string)"
    return func(args...)
end

#=
julia -e sleep(120) -- \
  /Users/cvogt/.julia/dev/rayjll/venv/lib/python3.10/site-packages/ray/cpp/default_worker \
  --ray_plasma_store_socket_name=/tmp/ray/session_2023-08-09_14-14-28_230005_27400/sockets/plasma_store \
  --ray_raylet_socket_name=/tmp/ray/session_2023-08-09_14-14-28_230005_27400/sockets/raylet \
  --ray_node_manager_port=57236 \
  --ray_address=127.0.0.1:6379 \
  --ray_redis_password= \
  --ray_session_dir=/tmp/ray/session_2023-08-09_14-14-28_230005_27400 \
  --ray_logs_dir=/tmp/ray/session_2023-08-09_14-14-28_230005_27400/logs \
  --ray_node_ip_address=127.0.0.1
=#
function start_worker(args=ARGS)
    s = ArgParseSettings()

    # Worker options are generated in the Raylet function `BuildProcessCommandArgs`
    # (https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/raylet/worker_pool.cc#L232)
    # and are parsed in Python here:
    # https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_private/workers/default_worker.py
    @add_arg_table! s begin
        "--ray_raylet_socket_name"
            dest_name = "raylet_socket"
            arg_type = String
        "--ray_plasma_store_socket_name"
            dest_name = "store_socket"
            arg_type = String
        "--ray_address"  # "127.0.0.1:6379"
            dest_name = "address"
            arg_type = String
            help="The ip address of the GCS"
        "--ray_node_manager_port"
            dest_name = "node_manager_port"
            arg_type = Int
        "--ray_node_ip_address"
            dest_name = "node_ip_address"
            required=true
            arg_type=String
            help="The ip address of the worker's node"
        "--ray_redis_password"
            dest_name = "redis_password"
            required=false
            arg_type=String
            default=""
            help="the password to use for Redis"
        "--ray_session_dir"
            dest_name = "session_dir"
        "--ray_logs_dir"
            dest_name = "logs_dir"
        "--runtime-env-hash"
            dest_name="runtime_env_hash"
            required=false
            arg_type=Int
            default=0
            help="The computed hash of the runtime env for this worker"
        "arg1"
            required = true
    end

    parsed_args = parse_args(args, s)

    _init_global_function_manager(parsed_args["address"])

    # TODO: pass "debug mode" as a flag somehow
    ENV["JULIA_DEBUG"] = "Ray"
    logfile = joinpath(parsed_args["logs_dir"], "julia_worker_$(getpid()).log")
    global_logger(FileLogger(logfile; append=true, always_flush=true))

    @info "Starting Julia worker runtime with args" parsed_args

    return rayjll.start_worker(parsed_args["raylet_socket"],
                               parsed_args["store_socket"],
                               parsed_args["address"],
                               parsed_args["node_ip_address"],
                               parsed_args["node_manager_port"],
                               task_executor)

end
