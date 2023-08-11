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

function node_manager_port()
    line = open("/tmp/ray/session_latest/logs/raylet.out") do io
        while !eof(io)
            line = readline(io)
            if contains(line, "NodeManager server started")
                return line
            end
        end
    end

    m = match(r"port (\d+)", line)
    return m !== nothing ? parse(Int, m[1]) : error("Unable to find port")
end

initialize_coreworker() = initialize_coreworker(node_manager_port())

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

function task_executor()
    @info "task_executor called"
    return getpid()
end

project_dir() = dirname(Pkg.project().path)
submit_task() = _submit_task(project_dir())


#=
julia -e sleep(120) -- \
  /Users/cvogt/.julia/dev/ray_core_worker_julia_jll/venv/lib/python3.10/site-packages/ray/cpp/default_worker \
  --ray_plasma_store_socket_name=/tmp/ray/session_2023-08-09_14-14-28_230005_27400/sockets/plasma_store \
  --ray_raylet_socket_name=/tmp/ray/session_2023-08-09_14-14-28_230005_27400/sockets/raylet \
  --ray_node_manager_port=57236 --ray_address=127.0.0.1:6379 \
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

    open(joinpath(parsed_args["logs_dir"], "julia_worker.log"), "w+") do io
        global_logger(SimpleLogger(io))
        @info "Testing"
        initialize_coreworker_worker(
            parsed_args["node_manager_port"],
            CxxWrap.@safe_cfunction(task_executor, Int32, ()),
        )
    end
end
