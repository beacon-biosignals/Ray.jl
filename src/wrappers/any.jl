using CxxWrap
using CxxWrap.StdLib: StdVectorAllocated
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

#####
##### runtime wrappers
#####

function start_worker(raylet_socket, store_socket, ray_address, node_ip_address,
                      node_manager_port, task_executor::Function)
    # need to use `@eval` since `task_executor` is only defined at runtime
    cfunc = @eval CxxWrap.@safe_cfunction($(task_executor),
                                          Int32,
                                          # Note (omus): If you are trying to figure
                                          # out what type to pass in here I recommend
                                          # starting with `Any`. This will cause
                                          # failures at runtime that show up in the
                                          # "raylet.err" logs which tell you the type:
                                          # ```
                                          # libc++abi: terminating due to uncaught
                                          # exception of type std::runtime_error:
                                          # Incorrect argument type for cfunction at
                                          # position 1, expected: RayFunctionAllocated,
                                          # obtained: Any
                                          # ```
                                          # Using `ConstCxxRef` doesn't seem supported
                                          # (i.e. `const &`)
                                          (RayFunctionAllocated, std::vector))

    @info "cfunction generated!"
    return initialize_coreworker_worker(raylet_socket, store_socket,
                                        ray_address, node_ip_address,
                                        node_manager_port, cfunc)
end
