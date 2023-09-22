using CxxWrap
using CxxWrap.StdLib: StdVector, SharedPtr
using Serialization

const STATUS_CODE_SYMBOLS = (:OK,
    :OutOfMemory,
    :KeyError,
    :TypeError,
    :Invalid,
    :IOError,
    :UnknownError,
    :NotImplemented,
    :RedisError,
    :TimedOut,
    :Interrupted,
    :IntentionalSystemExit,
    :UnexpectedSystemExit,
    :CreationTaskError,
    :NotFound,
    :Disconnected,
    :SchedulingCancelled,
    :ObjectExists,
    :ObjectNotFound,
    :ObjectAlreadySealed,
    :ObjectStoreFull,
    :TransientObjectStoreFull,
    :GrpcUnavailable,
    :GrpcUnknown,
    :OutOfDisk,
    :ObjectUnknownOwner,
    :RpcError,
    :OutOfResource,
    :ObjectRefEndOfStream)

@eval begin
    $(_enum_getproperty_expr(StatusCode, STATUS_CODE_SYMBOLS))
    $(_enum_propertynames_expr(StatusCode, STATUS_CODE_SYMBOLS))
end

const LANGUAGE_SYMBOLS = (:PYTHON, :JAVA, :CPP, :JULIA)

@eval begin
    $(_enum_getproperty_expr(Language, LANGUAGE_SYMBOLS))
    $(_enum_propertynames_expr(Language, LANGUAGE_SYMBOLS))
end

const WORKER_TYPE_SYMBOLS = (:WORKER, :DRIVER, :SPILL_WORKER, :RESTORE_WORKER)

@eval begin
    $(_enum_getproperty_expr(WorkerType, WORKER_TYPE_SYMBOLS))
    $(_enum_propertynames_expr(WorkerType, WORKER_TYPE_SYMBOLS))
end

function check_status(status::Status)
    ok(status) && return nothing

    msg = message(status)

    # TODO: Implement throw custom exception types like in:
    # _raylet.pyx:437
    error(msg)
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
##### Buffer
#####

NullPtr(::Type{Buffer}) = BufferFromNull()

#####
##### ObjectID
#####

FromHex(::Type{ObjectID}, str::AbstractString) = ObjectIDFromHex(str)
FromRandom(::Type{ObjectID}) = ObjectIDFromRandom()

#####
##### TaskArg
#####

function CxxWrap.StdLib.UniquePtr(ptr::Union{Ptr{Nothing},
    CxxPtr{<:TaskArgByReference},
    CxxPtr{<:TaskArgByValue}})
    return unique_ptr(ptr)
end

#####
##### Upstream fixes
#####

function Base.take!(buffer::CxxWrap.CxxWrapCore.SmartPointer{<:Buffer})
    buffer_ptr = Ptr{UInt8}(Data(buffer[]).cpp_object)
    buffer_size = Size(buffer[])
    vec = Vector{UInt8}(undef, buffer_size)
    unsafe_copyto!(Ptr{UInt8}(pointer(vec)), buffer_ptr, buffer_size)
    return vec
end

# Work around this: https://github.com/JuliaInterop/CxxWrap.jl/issues/300
function Base.push!(v::CxxPtr{StdVector{T}}, el::T) where {T<:SharedPtr{RayObject}}
    return push!(v, CxxRef(el))
end

# Work around CxxWrap's `push!` always dereferencing our value via `@cxxdereference`
# https://github.com/JuliaInterop/CxxWrap.jl/blob/0de5fbc5673367adc7e725cfc6e1fc6a8f9240a0/src/StdLib.jl#L78-L81
function Base.push!(v::StdVector{CxxPtr{TaskArg}}, el::CxxPtr{<:TaskArg})
    _push_back(v, el)
    return v
end

# XXX: Need to convert julia vectors to StdVector and build the
# `std::unordered_map` for resources. This function helps us avoid having
# CxxWrap as a direct dependency in Ray.jl
function _submit_task(fd, args, serialized_runtime_env_info, resources::AbstractDict)
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

    @info "worker exiting `ray_julia_jll.initialize_worker`"
    return result
end
