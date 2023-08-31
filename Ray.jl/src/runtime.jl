const JOB_RUNTIME_ENV = Ref{RuntimeEnv}()

macro ray_import(ex)
    Ray = gensym(:Ray)
    result = quote
        import Ray as $Ray
        $Ray._ray_import($Ray.RuntimeEnv(; package_imports=$(QuoteNode(ex))))
        $ex
    end

    return esc(result)
end

function _ray_import(runtime_env::RuntimeEnv)
    if isassigned(JOB_RUNTIME_ENV)
        error("`@ray_import` must be used before `Ray.init` and can only be called once")
    end

    JOB_RUNTIME_ENV[] = runtime_env
    return nothing
end

struct RayRemoteException <: Exception
    pid::Int
    task_name::String
    captured::CapturedException
end

function Base.showerror(io::IO, re::RayRemoteException)
    print(io, "on Ray task \"$(re.task_name)\" with PID $(re.pid): ")
    showerror(io, re.captured)
end

"""
    const GLOBAL_STATE_ACCESSOR::Ref{ray_jll.GlobalStateAccessor}

Global binding for GCS client interface to access global state information.
Currently only used to get the next job ID.

This is set during `init` and used there to get the Job ID for the driver.
"""
const GLOBAL_STATE_ACCESSOR = Ref{ray_jll.GlobalStateAccessor}()

# env var to control whether logs are sent do stderr or to file.  if "1", sent
# to stderr; otherwise, will be sent to files in `/tmp/ray/session_latest/logs/`
# https://github.com/beacon-biosignals/ray/blob/4ceb62daaad05124713ff9d94ffbdad35ee19f86/python/ray/_private/ray_constants.py#L198
const LOGGING_REDIRECT_STDERR_ENVIRONMENT_VARIABLE = "RAY_LOG_TO_STDERR"

function default_log_dir(session_dir)
    redirect_logs = Base.get(ENV, LOGGING_REDIRECT_STDERR_ENVIRONMENT_VARIABLE, "0") == "1"
    # realpath() resolves relative paths and symlinks, including the default
    # `/tmp/ray/session_latest/`.  this is defense against folks potentially
    # starting multiple ray sessions locally, which could cause the logs path to
    # change out from under us if we use the symlink directly.
    return redirect_logs ? "" : realpath(joinpath(session_dir, "logs"))
end

function init(runtime_env::Union{RuntimeEnv,Nothing}=nothing;
              session_dir="/tmp/ray/session_latest",
              logs_dir=default_log_dir(session_dir))
    # XXX: this is at best EXREMELY IMPERFECT check.  we should do something
    # more like what hte python Worker class does, getting node ID at
    # initialization and using that as a proxy for whether it's connected or not
    #
    # https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/python/ray/_private/worker.py#L421
    if isassigned(FUNCTION_MANAGER)
        @warn "Ray already initialized, skipping..."
        return nothing
    end

    if isnothing(runtime_env)
        # Set default for `JOB_RUNTIME_ENV` when `Ray.init` is called before `@ray_import`.
        # This ensures a call to `@ray_import` after `Ray.init` will fail.
        if !isassigned(JOB_RUNTIME_ENV)
            JOB_RUNTIME_ENV[] = RuntimeEnv()
        end

        runtime_env = JOB_RUNTIME_ENV[]
    end

    # TODO: use something like the java config bootstrap address (?) to get this
    # https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl/issues/52
    # information instead of parsing logs?  I can't quite tell where it's coming
    # from (set from a `ray.address` config option):
    # https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/java/runtime/src/main/java/io/ray/runtime/config/RayConfig.java#L165-L171

    # we use session_dir here instead of logs_dir since logs_dir can be set to
    # "" to disable file logging without using env var
    args = parse_ray_args_from_raylet_out(session_dir)
    gcs_address = args[3]

    opts = ray_jll.GcsClientOptions(gcs_address)
    GLOBAL_STATE_ACCESSOR[] = ray_jll.GlobalStateAccessor(opts)
    ray_jll.Connect(GLOBAL_STATE_ACCESSOR[]) ||
        error("Failed to connect to Ray GCS at $(gcs_address)")
    atexit(() -> ray_jll.Disconnect(GLOBAL_STATE_ACCESSOR[]))

    job_id = ray_jll.GetNextJobID(GLOBAL_STATE_ACCESSOR[])

    job_config = JobConfig(RuntimeEnvInfo(runtime_env))
    serialized_job_config = _serialize(job_config)

    ray_jll.initialize_driver(args..., job_id, logs_dir, serialized_job_config)
    atexit(ray_jll.shutdown_driver)

    _init_global_function_manager(gcs_address)

    return nothing
end

# this could go in JLL but if/when global worker is hosted here it's better to
# keep it local
get_current_job_id() = ray_jll.ToInt(ray_jll.GetCurrentJobId())

"""
    get_task_id() -> String

Get the current task ID for this worker in hex format.
"""
get_task_id() = String(ray_jll.Hex(ray_jll.GetCurrentTaskId()))

function parse_ray_args_from_raylet_out(session_dir)
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
    line = open(joinpath(session_dir, "logs", "raylet.out")) do io
        while !eof(io)
            line = readline(io)
            if contains(line, "Starting agent process")
                return line
            end
        end
    end

    line !== nothing || error("Unable to locate agent process information")

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
    # https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl/issues/53
    @info "Raylet socket: $raylet, Object store: $store, Node IP: $node_ip, Node port: $node_port, GCS Address: $gcs_address"

    return (raylet, store, gcs_address, node_ip, node_port)
end

initialize_coreworker_driver(args...) = ray_jll.initialize_coreworker_driver(args...)

function submit_task(f::Function, args::Tuple, kwargs::NamedTuple=NamedTuple();
                     runtime_env::Union{RuntimeEnv,Nothing}=nothing,
                     resources::Dict{String,Float64}=Dict("CPU" => 1.0))
    export_function!(FUNCTION_MANAGER[], f, get_current_job_id())
    fd = ray_jll.function_descriptor(f)
    task_args = prepare_task_args(flatten_args(args, kwargs))

    task_args_alt = StdVector{CxxPtr{ray_jll.TaskArg}}()
    for task_arg in task_args
        push!(task_args_alt, CxxRef(task_arg))
    end

    serialized_runtime_env_info = if !isnothing(runtime_env)
        _serialize(RuntimeEnvInfo(runtime_env))
    else
        ""
    end

    return GC.@preserve args ray_jll._submit_task(fd,
                                                  task_args_alt,
                                                  serialized_runtime_env_info,
                                                  resources)
end

function serialize_as_bytes(data)
    bytes = Vector{UInt8}()
    io = IOBuffer(bytes; write=true)
    serialize(io, data)
    return bytes
end

# TODO: be smarter about handling flattened args
# Adapted from `prepare_args_internal`:
# https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_raylet.pyx#L673
function prepare_task_args(args)
    ray_config = ray_jll.RayConfigInstance()
    put_threshold = ray_jll.max_direct_call_object_size(ray_config)
    total_inlined = 0
    rpc_inline_threshold = ray_jll.task_rpc_inlined_bytes_limit(ray_config)
    # core_worker = ray_jll.GetCoreWorker()
    rpc_address = ray_jll.GetRpcAddress()

    # TODO: put_arg_call_site

    task_args = []
    for arg in args
        # if arg isa ObjectRef
        #     oid = arg.oid
        #     op_status = ray_jll.GetOwnerAddress(core_worker, oid, owner_address)
        #             c_arg, &c_owner_address)
        #     check_status(op_status)
        #     push!(task_args,
        #         unique_ptr[CTaskArg](new CTaskArgByReference(
        #             c_arg,
        #             c_owner_address,
        #             arg.call_site())))
        # end

        serialized_arg = serialize_as_bytes(arg)
        serialized_arg_size = sizeof(serialized_arg)
        buffer = ray_jll.LocalMemoryBuffer(serialized_arg, serialized_arg_size, true)

        if (serialized_arg_size <= put_threshold &&
            serialized_arg_size + total_inlined <= rpc_inline_threshold)

            push!(task_args, ray_jll.SharedPtrTaskArgByValue(ray_jll.RayObject(buffer)))
            total_inlined += serialized_arg_size
        else
            oid = ray_jll.put(buffer)
            call_site = ""
            push!(task_args, ray_jll.SharedPtrTaskArgByReference(oid, rpc_address, call_site))
        end
    end

    return task_args
end

function task_executor(ray_function, returns_ptr, task_args_ptr, task_name,
                       application_error, is_retryable_error)
    returns = ray_jll.cast_to_returns(returns_ptr)
    task_args = ray_jll.cast_to_task_args(task_args_ptr)

    local result
    try
        @info "task_executor: called for JobID $(ray_jll.GetCurrentJobId())"
        fd = ray_jll.GetFunctionDescriptor(ray_function)
        # TODO: may need to wait for function here...
        @debug "task_executor: importing function" fd
        func = import_function!(FUNCTION_MANAGER[],
                                ray_jll.unwrap_function_descriptor(fd),
                                get_current_job_id())

        flattened = map(Ray.get, task_args)
        args, kwargs = recover_args(flattened)

        @info begin
            param_str = join((string("::", typeof(arg)) for arg in args), ", ")
            if !isempty(kwargs)
                param_str *= "; "
                param_str *= join((string(k, "::", typeof(v)) for (k, v) in kwargs), ", ")
            end
            "Calling $func($param_str)"
        end

        result = func(args...; kwargs...)
    catch e
        # timestamp format to match python time.time()
        # https://docs.python.org/3/library/time.html#time.time
        timestamp = time()
        captured = CapturedException(e, catch_backtrace())
        @error "Caught exception during task execution" exception=captured
        # XXX: for some reason CxxWrap does not allow this:
        #
        # application_error[] = err_msg
        #
        # so we use a cpp function whose only job is to assign the value to the
        # pointer
        err_msg = sprint(showerror, captured)
        status = ray_jll.report_error(application_error, err_msg, timestamp)
        # XXX: we _can_ set _this_ return pointer here for some reason, and it
        # was _harder_ to toss it back over the fence to the wrapper C++ code
        is_retryable_error[] = ray_jll.CxxBool(false)
        @debug "push error status: $status"

        result = RayRemoteException(getpid(), task_name, captured)
    end

    # TODO: remove - useful for now for debugging
    # https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl/issues/53
    @info "Result: $result"

    # TODO: support multiple return values
    # https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl/issues/54
    push!(returns, to_serialized_buffer(result))

    return nothing
end

#=
julia -e sleep(120) -- \
  /Users/cvogt/.julia/dev/ray_core_worker_julia_jll/venv/lib/python3.10/site-packages/ray/cpp/default_worker \
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
        "--startup_token"
            dest_name="startup_token"
            required=false
            arg_type=Int
            default=0
        "arg1"
            required = true
    end

    parsed_args = parse_args(args, s)

    _init_global_function_manager(parsed_args["address"])

    # Load top-level package loading statements (e.g. `import X` or `using X`) to ensure
    # tasks have access to dependencies.
    if haskey(ENV, "JULIA_RAY_PACKAGE_IMPORTS")
        io = IOBuffer(ENV["JULIA_RAY_PACKAGE_IMPORTS"])
        pkg_imports = deserialize(Base64DecodePipe(io))
        @info "Package loading expression:\n$pkg_imports"
        Base.eval(Main, pkg_imports)
    end

    # TODO: pass "debug mode" as a flag somehow
    # https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl/issues/53
    ENV["JULIA_DEBUG"] = "Ray"
    logfile = joinpath(parsed_args["logs_dir"], "julia_worker_$(getpid()).log")
    global_logger(FileLogger(logfile; append=true, always_flush=true))

    @info "Starting Julia worker runtime with args" parsed_args

    return ray_jll.initialize_worker(parsed_args["raylet_socket"],
                                    parsed_args["store_socket"],
                                    parsed_args["address"],
                                    parsed_args["node_ip_address"],
                                    parsed_args["node_manager_port"],
                                    parsed_args["startup_token"],
                                    parsed_args["runtime_env_hash"],
                                    task_executor)
end
