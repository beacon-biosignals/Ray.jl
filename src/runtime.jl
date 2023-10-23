"""
    const GLOBAL_STATE_ACCESSOR::Ref{ray_jll.GlobalStateAccessor}

Global binding for GCS client interface to access global state information.
This is set during [`Ray.init`](@ref) and used there to get the the raylet name, object
store name, node manager port, and the next job IDJob ID for the driver.
"""
const GLOBAL_STATE_ACCESSOR = Ref{ray_jll.GlobalStateAccessor}()

# env var to control whether logs are sent do stderr or to file.  if "1", sent
# to stderr; otherwise, will be sent to files in `/tmp/ray/session_latest/logs/`
# https://github.com/beacon-biosignals/ray/blob/4ceb62daaad05124713ff9d94ffbdad35ee19f86/python/ray/_private/ray_constants.py#L198
const LOGGING_REDIRECT_STDERR_ENVIRONMENT_VARIABLE = "RAY_LOG_TO_STDERR"

const JOB_RUNTIME_ENV = Ref{RuntimeEnv}()

# In ray-2.5.1 this is constant but in later versions it's read from NODE_IP_ADDRESS.json
# https://github.com/ray-project/ray/blob/a03efd9931128d387649dd48b0e4864b43d3bfb4/python/ray/_private/services.py#L650-L658
const NODE_IP_ADDRESS = "127.0.0.1"

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

    #gcs-address=127.0.0.1:6379
    gcs_address = read("/tmp/ray/ray_current_cluster", String)

    opts = ray_jll.GcsClientOptions(gcs_address)
    GLOBAL_STATE_ACCESSOR[] = ray_jll.GlobalStateAccessor(opts)
    ray_jll.Connect(GLOBAL_STATE_ACCESSOR[]) ||
        error("Failed to connect to Ray GCS at $(gcs_address)")
    atexit(() -> ray_jll.Disconnect(GLOBAL_STATE_ACCESSOR[]))

    job_id = ray_jll.GetNextJobID(GLOBAL_STATE_ACCESSOR[])

    # When submitting a job via `ray job submit` this metadata includes the
    # "job_submission_id" which lets Ray know that this driver is associated with a
    # submission ID.
    metadata = if haskey(ENV, "RAY_JOB_CONFIG_JSON_ENV_VAR")
        json = JSON3.read(ENV["RAY_JOB_CONFIG_JSON_ENV_VAR"])
        Dict(string(k) => v for (k, v) in json.metadata)
    else
        Dict()
    end

    job_config = JobConfig(RuntimeEnvInfo(runtime_env), metadata)
    serialized_job_config = _serialize(job_config)

    raylet, store, node_port = get_node_to_connect_for_driver(GLOBAL_STATE_ACCESSOR, NODE_IP_ADDRESS)

    # TODO: downgrade to debug
    # https://github.com/beacon-biosignals/Ray.jl/issues/53
    @info begin
        "Raylet socket: $raylet, Object store: $store, Node IP: $NODE_IP_ADDRESS, " *
        "Node port: $node_port, GCS Address: $gcs_address, JobID: $job_id"
    end

    ray_jll.initialize_driver(raylet,
                              store,
                              gcs_address,
                              NODE_IP_ADDRESS,
                              node_port,
                              job_id,
                              logs_dir,
                              serialized_job_config)

    atexit(ray_jll.shutdown_driver)

    _init_global_function_manager(gcs_address)

    return nothing
end

# TODO: Python Ray returns a string:
# https://docs.ray.io/en/latest/ray-core/api/doc/ray.runtime_context.RuntimeContext.get_job_id.html

"""
    get_job_id() -> UInt32

Get the current job ID for this worker or driver. Job ID is the id of your Ray drivers that
create tasks.
"""
get_job_id() = ray_jll.ToInt(ray_jll.GetCurrentJobId(ray_jll.GetCoreWorker()))::UInt32

"""
    get_task_id() -> String

Get the current task ID for this worker in hex format.
"""
get_task_id() = String(ray_jll.Hex(ray_jll.GetCurrentTaskId(ray_jll.GetCoreWorker())))

function get_node_to_connect_for_driver(global_state_accessor, node_ip_address)
    node_to_connect = CxxPtr(StdString())
    status = ray_jll.GetNodeToConnectForDriver(global_state_accessor[], node_ip_address,
                                               node_to_connect)
    node_info = ray_jll.ParseFromString(ray_jll.GcsNodeInfo, node_to_connect[])

    raylet_socket_name = ray_jll.raylet_socket_name(node_info)[]
    store_socket_name = ray_jll.object_store_socket_name(node_info)[]
    node_manager_port = ray_jll.node_manager_port(node_info)

    return (raylet_socket_name, store_socket_name, node_manager_port)
end

initialize_coreworker_driver(args...) = ray_jll.initialize_coreworker_driver(args...)

# TODO: Move task related code into a "task.jl" file
function submit_task(f::Function, args::Tuple, kwargs::NamedTuple=NamedTuple();
                     runtime_env::Union{RuntimeEnv,Nothing}=nothing,
                     resources::Dict{String,Float64}=Dict("CPU" => 1.0))
    export_function!(FUNCTION_MANAGER[], f, get_job_id())
    fd = ray_jll.function_descriptor(f)
    task_args = serialize_args(flatten_args(args, kwargs))

    serialized_runtime_env_info = if !isnothing(runtime_env)
        _serialize(RuntimeEnvInfo(runtime_env))
    else
        ""
    end

    oid = GC.@preserve task_args begin
        ray_jll._submit_task(fd,
                             transform_task_args(task_args),
                             serialized_runtime_env_info,
                             resources)
    end
    # CoreWorker::SubmitTask calls TaskManager::AddPendingTask which initializes
    # the local ref count to 1, so we don't need to do that here.
    return ObjectRef(oid; add_local_ref=false)
end

# Adapted from `prepare_args_internal`:
# https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_raylet.pyx#L673
function serialize_args(args)
    ray_config = ray_jll.RayConfigInstance()
    put_threshold = ray_jll.max_direct_call_object_size(ray_config)
    rpc_inline_threshold = ray_jll.task_rpc_inlined_bytes_limit(ray_config)
    record_call_site = ray_jll.record_ref_creation_sites(ray_config)

    worker = ray_jll.GetCoreWorker()
    rpc_address = ray_jll.GetRpcAddress(worker)

    total_inlined = 0

    # TODO: Ideally would be `ray_jll.TaskArg[]`:
    # https://github.com/beacon-biosignals/Ray.jl/issues/79
    task_args = Any[]
    for arg in args
        # Note: The Python `prepare_args_internal` function checks if the `arg` is an
        # `ObjectRef` and in that case uses the object ID to directly make a
        # `TaskArgByReference`. However, as the `args` here are flattened the `arg` will
        # always be a `Pair` (or a list in Python). I suspect this Python code path just
        # dead code so we'll exclude it from ours.

        ray_obj = serialize_to_ray_object(arg)
        serialized_arg_size = ray_jll.GetSize(ray_obj[])

        # Inline arguments which are small and if there is room
        task_arg = if (serialized_arg_size <= put_threshold &&
                       serialized_arg_size + total_inlined <= rpc_inline_threshold)
            total_inlined += serialized_arg_size
            ray_jll.TaskArgByValue(ray_obj)
        else
            nested_ids = ray_jll.GetNestedRefIds(ray_obj[])
            oid = CxxPtr(ray_jll.ObjectID())
            status = ray_jll.put(ray_obj, nested_ids, oid)
            Symbol(status) == :OK || error("ray_julia_jll.put returned Status::$status")
            # TODO: Add test for populating `call_site`
            call_site = record_call_site ? sprint(Base.show_backtrace, backtrace()) : ""
            ray_jll.TaskArgByReference(oid[], rpc_address, call_site)
        end

        push!(task_args, task_arg)
    end

    return task_args
end

function transform_task_args(task_args)
    task_arg_ptrs = StdVector{CxxPtr{ray_jll.TaskArg}}()
    for task_arg in task_args
        push!(task_arg_ptrs, CxxPtr(task_arg))
    end
    return task_arg_ptrs
end

function task_executor(ray_function, returns_ptr, task_args_ptr, task_name,
                       application_error, is_retryable_error)
    returns = ray_jll.cast_to_returns(returns_ptr)
    task_args = ray_jll.cast_to_task_args(task_args_ptr)
    worker = ray_jll.GetCoreWorker()

    local result
    try
        @info "task_executor: called for JobID $(get_job_id())"
        fd = ray_jll.GetFunctionDescriptor(ray_function)
        # TODO: may need to wait for function here...
        @debug "task_executor: importing function" fd
        func = import_function!(FUNCTION_MANAGER[],
                                ray_jll.unwrap_function_descriptor(fd),
                                get_job_id())

        flattened = map(Ray.deserialize_from_ray_object, task_args)
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
        @error "Caught exception during task execution" exception = captured
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

        result = RayTaskError(task_name, captured)
    end

    # TODO: remove - useful for now for debugging
    # https://github.com/beacon-biosignals/Ray.jl/issues/53
    @info "Result: $result"

    # TODO: support multiple return values
    # https://github.com/beacon-biosignals/Ray.jl/issues/54

    ray_obj = serialize_to_ray_object(result)
    push!(returns, ray_obj)

    return nothing
end

#=
julia -e 'using Ray; start_worker()' -- \
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

    #! format: off
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
            help = "The ip address of the GCS"
        "--ray_node_manager_port"
            dest_name = "node_manager_port"
            arg_type = Int
        "--ray_node_ip_address"
            dest_name = "node_ip_address"
            required = true
            arg_type = String
            help = "The ip address of the worker's node"
        "--ray_redis_password"
            dest_name = "redis_password"
            required = false
            arg_type = String
            default = ""
            help = "the password to use for Redis"
        "--ray_session_dir"
            dest_name = "session_dir"
        "--ray_logs_dir"
            dest_name = "logs_dir"
        "--runtime-env-hash"
            dest_name = "runtime_env_hash"
            required = false
            arg_type = Int
            default = 0
            help = "The computed hash of the runtime env for this worker"
        "--startup_token"
            dest_name = "startup_token"
            required = false
            arg_type = Int
            default = 0
    end
    #! format: on

    parsed_args = parse_args(args, s)

    # TODO: pass "debug mode" as a flag somehow
    # https://github.com/beacon-biosignals/Ray.jl/issues/53
    ENV["JULIA_DEBUG"] = "Ray"
    logfile = joinpath(parsed_args["logs_dir"], "julia_worker_$(getpid()).log")
    global_logger(timestamp_logger(FileLogger(logfile; append=true, always_flush=true)))

    _init_global_function_manager(parsed_args["address"])

    # Load top-level package loading statements (e.g. `import X` or `using X`) to ensure
    # tasks have access to dependencies.
    if haskey(ENV, "JULIA_RAY_PACKAGE_IMPORTS")
        io = IOBuffer(ENV["JULIA_RAY_PACKAGE_IMPORTS"])
        pkg_imports = deserialize(Base64DecodePipe(io))
        @info "Package loading expression:\n$pkg_imports"
        Base.eval(Main, pkg_imports)
    end

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

function timestamp_logger(logger, df::DateFormat=dateformat"yyyy-mm-dd HH:MM:SS,sss")
    return TransformerLogger(logger) do log
        return merge(log, (; message="$(Dates.format(now(), df)) $(log.message)"))
    end
end
