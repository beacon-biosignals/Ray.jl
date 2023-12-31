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

const ERROR_TYPE_SYMBOLS = (:WORKER_DIED,
                            :ACTOR_DIED,
                            :OBJECT_UNRECONSTRUCTABLE,
                            :TASK_EXECUTION_EXCEPTION,
                            :OBJECT_IN_PLASMA,
                            :TASK_CANCELLED,
                            :ACTOR_CREATION_FAILED,
                            :RUNTIME_ENV_SETUP_FAILED,
                            :OBJECT_LOST,
                            :OWNER_DIED,
                            :OBJECT_DELETED,
                            :DEPENDENCY_RESOLUTION_FAILED,
                            :OBJECT_UNRECONSTRUCTABLE_MAX_ATTEMPTS_EXCEEDED,
                            :OBJECT_UNRECONSTRUCTABLE_LINEAGE_EVICTED,
                            :OBJECT_FETCH_TIMED_OUT,
                            :LOCAL_RAYLET_DIED,
                            :TASK_PLACEMENT_GROUP_REMOVED,
                            :ACTOR_PLACEMENT_GROUP_REMOVED,
                            :TASK_UNSCHEDULABLE_ERROR,
                            :ACTOR_UNSCHEDULABLE_ERROR,
                            :OUT_OF_DISK_ERROR,
                            :OBJECT_FREED,
                            :OUT_OF_MEMORY,
                            :NODE_DIED)

# Generate the following methods for our wrapped enum types:
# - A constructor allowing you to create a value via a `Symbol` (e.g. `StatusCode(:OK)`).
# - A `Symbol` method allowing you convert a enum value to a `Symbol` (e.g. `Symbol(OK)`).
# - A `instances` method allowing you to get a list of all enum values (e.g. `instances(StatusCode)`).
@eval begin
    $(_enum_expr(:StatusCode, STATUS_CODE_SYMBOLS))
    $(_enum_expr(:Language, LANGUAGE_SYMBOLS))
    $(_enum_expr(:WorkerType, WORKER_TYPE_SYMBOLS))
    $(_enum_expr(:ErrorType, ERROR_TYPE_SYMBOLS))
end

function check_status(status::Status)
    ok(status) && return nothing

    msg = message(status)

    # TODO: Implement throw custom exception types like in:
    # _raylet.pyx:437
    error(msg)

    return nothing
end

function Connect(body, client::JuliaGcsClient)
    status = Connect(client)
    check_status(status)
    try
        return body(client)
    finally
        Disconnect(client)
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

let msg_types = (Address, JobConfig, ObjectReference)
    for T in msg_types
        types = (Symbol(nameof(T), :Allocated), Symbol(nameof(T), :Dereferenced))
        for A in types, B in types
            @eval Base.:(==)(a::$A, b::$B) = SerializeAsString(a) == SerializeAsString(b)
        end
    end
end

function Serialization.serialize(s::AbstractSerializer, message::Message)
    serialized_message = SerializeAsString(message)

    serialize_type(s, Message)
    serialize(s, supertype(typeof(message)))
    serialize(s, String(serialized_message))

    return nothing
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{Message})
    T = deserialize(s)
    serialized_message = deserialize(s)

    message = T()
    ParseFromString(message, serialized_message)

    return message
end

#####
##### Address <: Message
#####

function Address(nt::NamedTuple)
    raylet_id = base64encode(Binary(FromHex(NodeID, nt.raylet_id)))
    worker_id = base64encode(Binary(FromHex(WorkerID, nt.worker_id)))
    nt = (; raylet_id, nt.ip_address, nt.port, worker_id)
    return JsonStringToMessage(Address, JSON3.write(nt))
end

function Base.show(io::IO, addr::Address)
    raylet_hex = Hex(FromBinary(NodeID, raylet_id(addr)))
    ip_addr_str = ip_address(addr)[]
    worker_hex = Hex(FromBinary(WorkerID, worker_id(addr)))

    print(io, "$Address((raylet_id=\"$raylet_hex\", ip_address=\"$ip_addr_str\", ")
    print(io, "port=$(port(addr)), worker_id=\"$worker_hex\"))")
    return nothing
end

#####
##### Buffer
#####

NullPtr(::Type{Buffer}) = BufferFromNull()

#####
##### BaseID
#####

const HEX_CODEUNITS = Tuple(UInt8['0':'9'; 'a':'f'; 'A':'F'])

function ishex(s::AbstractString)
    for i in 1:ncodeunits(s)
        codeunit(s, i) in HEX_CODEUNITS || return false
    end
    return true
end

for T in (:ObjectID, :JobID, :TaskID, :WorkerID, :NodeID)
    siz = eval(Symbol(T, :Size))()

    @eval begin
        Size(::Type{$T}) = $siz

        function FromBinary(::Type{$T}, str::AbstractString)
            # Perform this check on the Julia side as an invalid string will run `RAY_CHECK`
            # on the backend causing the Julia process to terminate:
            # https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/id.h#L433-L434
            if ncodeunits(str) != Size($T) && ncodeunits(str) != 0
                msg = "Expected binary size is $(Size($T)) or 0, provided data size is $(ncodeunits(str))"
                throw(ArgumentError(msg))
            end
            return $(Symbol(T, :FromBinary))(str)
        end

        function FromHex(::Type{$T}, str::AbstractString)
            # Perform these checks on the Julia side since an invalid length hex string will
            # use `RAY_LOG` and report a C-style error or a non-hex string with the correct
            # length will silently return `Nil($T)`.
            # https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/id.h#L459-L460
            # https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/id.h#L468-L473
            if length(str) != 2 * Size($T)
                msg = "Expected hex string length is 2 * $(Size($T)), provided length is $(length(str)). Hex string: $str"
                throw(ArgumentError(msg))
            elseif !ishex(str)
                throw(ArgumentError("Expected hex string, found: $str"))
            end
            return $(Symbol(T, :FromHex))(str)
        end

        $T(hex::AbstractString) = FromHex($T, hex)
        Nil(::Type{$T}) = $(Symbol(T, :Nil))()
        Base.hash(x::$T, h::UInt) = hash($T, hash(Hex(x), h))
    end

    # Conditionally define `FromRandom` for types that wrap the C++ function
    _FromRandom = Symbol(T, :FromRandom)
    isdefined(@__MODULE__(), _FromRandom) && @eval FromRandom(::Type{$T}) = $(_FromRandom)()

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
    sub_types = (Symbol(T, :Allocated), Symbol(T, :Dereferenced))
    for A in sub_types, B in sub_types
        @eval Base.:(==)(a::$A, b::$B) = Hex(a) == Hex(b)
    end
end

FromBinary(::Type{T}, ref::ConstCxxRef) where {T<:BaseID} = FromBinary(T, ref[])
FromBinary(::Type{T}, bytes) where {T<:BaseID} = FromBinary(T, String(deepcopy(bytes)))
FromHex(::Type{T}, ref::ConstCxxRef) where {T<:BaseID} = FromHex(T, ref[])

function Base.show(io::IO, id::BaseID)
    T = supertype(typeof(id))
    print(io, "$T(\"", Hex(id), "\")")
    return nothing
end

#####
##### JobID
#####

JobID(num::Integer) = FromInt(JobID, num)
FromInt(::Type{JobID}, num::Integer) = JobIDFromInt(num)
Base.show(io::IO, id::JobID) = print(io, "JobID(", ToInt(id), ")")

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
function _submit_task(fd, args, serialized_runtime_env_info, resources::AbstractDict,
                      max_retries)
    @debug "task resources: " resources
    resources = build_resource_requests(resources)
    return _submit_task(fd, args, serialized_runtime_env_info, resources, max_retries)
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
