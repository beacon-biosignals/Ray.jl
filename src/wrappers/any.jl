using CxxWrap
using CxxWrap.StdLib: StdVector, SharedPtr
using libcxxwrap_julia_jll

using Serialization

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

#####
##### Function descriptor wrangling
#####

# build a FunctionDescriptor from a julia function
function function_descriptor(f::Function)
    mod = string(parentmodule(f))
    name = string(nameof(f))
    hash = let io = IOBuffer()
        serialize(io, f)
        # hexidecimal string repr of hash
        string(Base.hash(io.data); base=16)
    end
    return function_descriptor(mod, name, hash)
end

Base.show(io::IO, fd::FunctionDescriptor) = print(io, ToString(fd))
Base.show(io::IO, fd::JuliaFunctionDescriptor) = print(io, ToString(fd))
function Base.propertynames(fd::JuliaFunctionDescriptor, private::Bool=false)
    public_properties = (:module_name, :function_name, :function_hash)
    return if private
        tuple(public_properties..., fieldnames(typeof(fd))...)
    else
        public_properties
    end
end

function Base.getproperty(fd::JuliaFunctionDescriptor, field::Symbol)
    return if field === :module_name
        # these return refs so we need to de-reference them
        ModuleName(fd)[]
    elseif field === :function_name
        FunctionName(fd)[]
    elseif field === :function_hash
        FunctionHash(fd)[]
    else
        Base.getfield(fd, field)
    end
end

Base.show(io::IO, status::Status) = print(io, ToString(status))
Base.show(io::IO, jobid::JobID) = print(io, Int(ToInt(jobid)))

const CORE_WORKER = Ref{CoreWorker}()

function GetCoreWorker()
    if !isassigned(CORE_WORKER)
        CORE_WORKER[] = _GetCoreWorker()[]
    end
    return CORE_WORKER[]
end

#####
##### Upstream fixes
#####

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

# Work around this: https://github.com/JuliaInterop/CxxWrap.jl/issues/300
function Base.push!(v::CxxPtr{StdVector{T}}, el::T) where T <: SharedPtr{LocalMemoryBuffer}
    return push!(v, CxxRef(el))
end

# XXX: Need to convert julia vectors to StdVector and build the
# `std::unordered_map` for resources. This function helps us avoid having
# CxxWrap as a direct dependency in Ray.jl
function _submit_task(fd, oids::AbstractVector, serialized_runtime_env_info, resources)
    # https://github.com/JuliaInterop/CxxWrap.jl/issues/367
    args = isempty(oids) ? StdVector{ObjectID}() : StdVector(oids)
    @debug "task resources: " resources
    resources = build_resource_requests(resources)
    return _submit_task(fd, args, serialized_runtime_env_info, resources)
end

# work around lack of wrapped `std::unordered_map`
function build_resource_requests(resources::Dict{<:AbstractString,<:Number})
    cpp_resources = CxxMapStringDouble()
    for (k, v) in pairs(resources)
        _setindex!(cpp_resources, float(v), k)
    end
    return cpp_resources
end

#####
##### runtime wrappers
#####

function initialize_worker(raylet_socket, store_socket, ray_address, node_ip_address,
                           node_manager_port, startup_token, runtime_env_hash,
                           task_executor::Function)

    # Note (omus): If you are trying to figure out what type to pass in here I recommend
    # starting with `Any`. This will cause failures at runtime that show up in the
    # "raylet.err" logs which tell you the type:
    #```
    # libc++abi: terminating due to uncaught exception of type std::runtime_error:
    # Incorrect argument type for cfunction at position 1, expected: RayFunctionAllocated,
    # obtained: Any
    # ```
    # Using `ConstCxxRef` doesn't seem supported (i.e. `const &`)
    arg_types = (RayFunctionAllocated, Ptr{Cvoid}, Ptr{Cvoid},
                 CxxWrap.StdLib.StdStringAllocated, CxxPtr{CxxWrap.StdString},
                 CxxPtr{CxxBool})
    # need to use `@eval` since `task_executor` is only defined at runtime
    cfunc = @eval @cfunction($(task_executor), Cvoid, ($(arg_types...),))

    @info "cfunction generated!"
    result = initialize_worker(raylet_socket, store_socket, ray_address, node_ip_address,
                               node_manager_port, startup_token, runtime_env_hash, cfunc)

    @info "worker exiting `ray_core_worker_julia_jll.initialize_worker`"
    return result
end
