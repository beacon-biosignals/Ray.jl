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

const LANGUAGE_SYMBOLS = (:PYTHON, :JAVA, :CPP, :JULIA)
const WORKER_TYPE_SYMBOLS = (:WORKER, :DRIVER, :SPILL_WORKER, :RESTORE_WORKER)

# Generate the following methods for our wrapped enum types:
# - A constructor allowing you to create a value via a `Symbol` (e.g. `StatusCode(:OK)`).
# - A `instances` method allowing you to get a list of all enum values (e.g. `instances(StatusCode)`)
@eval begin
    $(_enum_symbol_constructor_expr(StatusCode, STATUS_CODE_SYMBOLS))
    $(_enum_instances_expr(StatusCode, STATUS_CODE_SYMBOLS))

    $(_enum_symbol_constructor_expr(Language, LANGUAGE_SYMBOLS))
    $(_enum_instances_expr(Language, LANGUAGE_SYMBOLS))

    $(_enum_symbol_constructor_expr(WorkerType, WORKER_TYPE_SYMBOLS))
    $(_enum_instances_expr(WorkerType, WORKER_TYPE_SYMBOLS))
end

function check_status(status::Status)
    ok(status) && return nothing

    msg = message(status)

    # TODO: Implement throw custom exception types like in:
    # _raylet.pyx:437
    error(msg)

    return nothing
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
Base.show(io::IO, jobid::JobID) = print(io, ToInt(jobid))

const CORE_WORKER = Ref{Union{CoreWorker,Nothing}}()

function GetCoreWorker()
    if !isassigned(CORE_WORKER) || isnothing(CORE_WORKER[])
        CORE_WORKER[] = _GetCoreWorker()[]
    end
    return CORE_WORKER[]::CoreWorker
end

function shutdown_driver()
    _shutdown_driver()
    CORE_WORKER[] = nothing

    return nothing
end

#####
##### Message
#####

function ParseFromString(::Type{T}, str::AbstractString) where {T<:Message}
    message = T()
    ParseFromString(message, str)
    return message
end

function JsonStringToMessage(::Type{T}, json::AbstractString) where {T<:Message}
    message = T()
    JsonStringToMessage(json, CxxPtr(message))
    return message
end

#####
##### Address
#####

# there's annoying conversion from protobuf binary blobs for the "fields" so we
# handle it on the C++ side rather than wrapping everything.
Base.show(io::IO, addr::Address) = print(io, _string(addr))

#####
##### Buffer
#####

NullPtr(::Type{Buffer}) = BufferFromNull()

#####
##### JobID
#####

FromInt(::Type{JobID}, num::Integer) = JobIDFromInt(num)

#####
##### ObjectID
#####

FromHex(::Type{ObjectID}, str::AbstractString) = ObjectIDFromHex(str)
FromRandom(::Type{ObjectID}) = ObjectIDFromRandom()
FromNil(::Type{ObjectID}) = ObjectIDFromNil()

ObjectID(str::AbstractString) = FromHex(ObjectID, str)

Base.show(io::IO, x::ObjectID) = write(io, "ObjectID(\"", Hex(x), "\")")

# cannot believe I'm doing this...
#
# Because ObjectID is a CxxWrap-defined type, it has two subtypes:
# `ObjectIDAllocated` and `ObjectIDDereferenced`.  The first is returned when we
# construct directly or return by value, the second when you pull a ref out of
# say `std::vector<ObjectID>`.
#
# ObjectID is abstract, so the normal method definition:
#
# Base.:(==)(a::ObjectID, b::ObjectID) = Hex(a) == Hex(b)
#
# is shadowed by more specific fallbacks defined by CxxWrap.
const ObjectIDTypes = (ObjectIDAllocated, ObjectIDDereferenced)
for Ta in ObjectIDTypes, Tb in ObjectIDTypes
    @eval Base.:(==)(a::$Ta, b::$Tb) = Hex(a) == Hex(b)
end

Base.hash(x::ObjectID, h::UInt) = hash(ObjectID, hash(Hex(x), h))

#####
##### RayObject
#####

# Functions `get_data` and `get_metadata` inspired by `RayObjectsToDataMetadataPairs`:
# https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_raylet.pyx#L458-L475

function get_data(ptr::SharedPtr{RayObject})
    ray_obj = ptr[]
    return if HasData(ray_obj)
        take!(GetData(ray_obj))
    else
        nothing
    end
end

function get_metadata(ptr::SharedPtr{RayObject})
    ray_obj = ptr[]
    return if HasMetadata(ray_obj)
        # Unlike `GetData`, `GetMetadata` returns a _reference_ to a pointer to a buffer, so
        # we need to dereference the return value to get the pointer that `take!` expects.
        take!(GetMetadata(ray_obj)[])
    else
        nothing
    end
end

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
