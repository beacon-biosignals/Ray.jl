# export ray_core_worker_julia
export Language, WorkerType, start_worker

using CxxWrap
using libcxxwrap_julia_jll

JLLWrappers.@generate_wrapper_header("ray_core_worker_julia")
JLLWrappers.@declare_library_product(ray_core_worker_julia, "julia_core_worker_lib.so")
@wrapmodule(joinpath(artifact"ray_core_worker_julia", "julia_core_worker_lib.so"))

function __init__()
    JLLWrappers.@generate_init_header(libcxxwrap_julia_jll)
    JLLWrappers.@init_library_product(
        ray_core_worker_julia,
        "julia_core_worker_lib.so",
        RTLD_GLOBAL,
    )

    JLLWrappers.@generate_init_footer()
    @initcxx
end  # __init__()

function parse_ray_args()
   #==
    "Starting agent process with command: ...
    --node-ip-address=127.0.0.1 --metrics-export-port=60404 --dashboard-agent-port=60493
    --listen-port=52365 --node-manager-port=58888
    --object-store-name=/tmp/ray/session_2023-08-14_14-54-36_055139_41385/sockets/plasma_store
    --raylet-name=/tmp/ray/session_2023-08-14_14-54-36_055139_41385/sockets/raylet
    --temp-dir=/tmp/ray --session-dir=/tmp/ray/session_2023-08-14_14-54-36_055139_41385
    --runtime-env-dir=/tmp/ray/session_2023-08-14_14-54-36_055139_41385/runtime_resources
    --log-dir=/tmp/ray/session_2023-08-14_14-54-36_055139_41385/logs
    --logging-rotate-bytes=536870912 --logging-rotate-backup-count=5
    --session-name=session_2023-08-14_14-54-36_055139_41385
    --gcs-address=127.0.0.1:6379 --minimal --agent-id 470211272
   ==#
    line = open("/tmp/ray/session_latest/logs/raylet.out") do io
        while !eof(io)
            line = readline(io)
            if contains(line, "Starting agent process")
                return line
            end
        end
    end

    gcs_match = match(r"gcs-address=(([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{4})", line)
    gcs_address = gcs_match !== nothing ? gcs_match[1] : error("Unable to find GCS address")

    node_ip_match = match(r"node-ip-address=(([0-9]{1,3}\.){3}[0-9]{1,3})", line)
    node_ip = node_ip_match !== nothing ? node_ip_match[1] : error("Unable to find Node IP address")

    port_match = match(r"node-manager-port=([0-9]+)", line)
    node_port = port_match !== nothing ? parse(Int, port_match[1]) : error("Unable to find Node Manager port")

    return (node_ip, node_port, gcs_address)
end


initialize_coreworker() = function

    # TODO: are these defaults? can they be overwritten by user and/or Ray?
    raylet_socket = "/tmp/ray/session_latest/sockets/plasma_store"
    store_socket = "/tmp/ray/session_latest/sockets/raylet"

    node_ip, node_port, gcs_address = parse_ray_args()

    initialize_coreworker(raylet_socket, store_socket, gcs_address, node_port, node_ip)

    return nothing
end

# function Base.Symbol(language::Language)
#     return if language === PYTHON
#         :PYTHON
#     elseif field === JAVA
#         :JAVA
#     elseif field === CPP
#         :CPP
#     elseif field === JULIA
#         :JULIA
#     else
#         throw(ArgumentError("Unknown language: $language"))
#     end
# end

# Base.instances(::Type{Language}) = (PYTHON, JAVA, CPP, JULIA)

function Base.getproperty(::Type{Language}, field::Symbol)
    return if field === :PYTHON
        PYTHON
    elseif field === :JAVA
        JAVA
    elseif field === :CPP
        CPP
    elseif field === :JULIA
        JULIA
    else
        Base.getfield(Language, field)
    end
end

function Base.propertynames(::Type{Language}, private::Bool=false)
    public_properties = (:PYTHON, :JAVA, :CPP, :JULIA)
    return if private
        tuple(public_properties..., fieldnames(typeof(Language))...)
    else
        public_properties
    end
end

function Base.getproperty(::Type{WorkerType}, field::Symbol)
    return if field === :WORKER
        WORKER
    elseif field === :DRIVER
        DRIVER
    elseif field === :SPILL_WORKER
        SPILL_WORKER
    elseif field === :RESTORE_WORKER
        RESTORE_WORKER
    else
        Base.getfield(WorkerType, field)
    end
end

function Base.propertynames(::Type{WorkerType}, private::Bool=false)
    public_properties = (:WORKER, :DRIVER, :SPILL_WORKER, :RESTORE_WORKER)
    return if private
        tuple(public_properties..., fieldnames(typeof(WorkerType))...)
    else
        public_properties
    end
end

# build a FunctionDescriptor from a julia function
function function_descriptor(f::Function)
    mod = string(parentmodule(f))
    name = string(nameof(f))
    # TODO: actually hash the serialized function?
    hash = ""
    return BuildJulia(mod, name, hash)
end

Base.show(io::IO, fd::FunctionDescriptor) = print(io, ToString(fd))
Base.show(io::IO, fd::JuliaFunctionDescriptor) = print(io, ToString(fd))
Base.show(io::IO, status::Status) = print(io, ToString(status))

# Works around what appears to be a CxxWrap issue
function put(buffer::CxxWrap.StdLib.SharedPtr{LocalMemoryBuffer})
    return put(CxxWrap.CxxWrapCore.__cxxwrap_smartptr_cast_to_base(buffer))
end

function Base.take!(buffer::CxxWrap.CxxWrapCore.SmartPointer{<:Buffer})
    buffer_ptr = Ptr{UInt8}(Data(buffer[]).cpp_object)
    buffer_size = Size(buffer[])
    vec = Vector{UInt8}(undef, buffer_size)
    unsafe_copyto!(Ptr{UInt8}(pointer(vec)), buffer_ptr, buffer_size)
    return vec
end

function task_executor(ray_function)
    @info "task_executor called"
    fd = GetFunctionDescriptor(ray_function)
    func = eval(@__MODULE__, Meta.parse(CallString(fd)))
    @info "Calling $func"
    return func()
end

project_dir() = dirname(Pkg.project().path)

function submit_task(f::Function)
    fd = function_descriptor(f)
    return _submit_task(project_dir(), fd)
end

#=
julia -e sleep(120) -- \
  /Users/cvogt/.julia/dev/ray_core_worker_julia_jll/venv/lib/python3.10/site-packages/ray/cpp/default_worker \
  --ray_plasma_store_socket_name=/tmp/ray/session_2023-08-09_14-14-28_230005_27400/sockets/plasma_store \
  --ray_raylet_socket_name=/tmp/ray/session_2023-08-09_14-14-28_230005_27400/sockets/raylet \
  --ray_node_manager_port=57236
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

    # Note (omus): Logging is currently limited to a single worker as all workers attempt to
    # write to the same file.
    global_logger(FileLogger(joinpath(parsed_args["logs_dir"], "julia_worker.log");
                             append=true, always_flush=true))
    @info "Testing"
    initialize_coreworker_worker(
        parsed_args["node_manager_port"],
        parsed_args["raylet_socket"],
        parsed_args["store_socket"],
        parsed_args["address"],
        parsed_args["node_manager_port"],
        parsed_args["node_ip_address"],
        parsed_args["logs_dir"],
        parsed_args["runtime_env_hash"],
        CxxWrap.@safe_cfunction(
            task_executor,
            Int32,

            # Note (omus): If you are trying to figure out what type to pass in here I
            # recommend starting with `Any`. This will cause failures at runtime that
            # show up in the "raylet.err" logs which tell you the type:
            # ```
            # libc++abi: terminating due to uncaught exception of type
            # std::runtime_error: Incorrect argument type for cfunction at position 1,
            # expected: RayFunctionAllocated, obtained: Any
            # ```
            # Using `ConstCxxRef` doesn't seem supported (i.e. `const &`)
            (RayFunctionAllocated,),
        ),
    )
end
