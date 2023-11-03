struct OwnershipInfo
    owner_address::ray_jll.Address
    serialized_object_status::String
end

mutable struct RaySerializer{I<:IO} <: AbstractSerializer
    # Fields required by all AbstractSerializers
    io::I
    counter::Int
    table::IdDict{Any,Any}
    pending_refs::Vector{Int}
    version::Int

    # Inlined object references encountered during serializing/deserialization
    object_refs::Set{ObjectRef}

    # Deserialized object reference metadata used for registering ownership
    object_owner::Dict{ObjectRef,OwnershipInfo}

    function RaySerializer{I}(io::I) where {I<:IO}
        version = Serialization.ser_version
        object_refs = Set{ObjectRef}()
        object_owner = Dict{ObjectRef,OwnershipInfo}()

        return new(io, 0, IdDict(), Int[], version, object_refs, object_owner)
    end
end

RaySerializer(io::IO) = RaySerializer{typeof(io)}(io)
RaySerializer(bytes::Vector{UInt8}) = RaySerializer{IOBuffer}(IOBuffer(bytes; write=true))

function Base.getproperty(s::RaySerializer, f::Symbol)
    if f === :object_ids
        return Set{ray_jll.ObjectIDAllocated}(getproperty.(s.object_refs, :oid))
    else
        return getfield(s, f)
    end
end

function Serialization.reset_state(s::RaySerializer)
    empty!(s.object_refs)
    return invoke(reset_state, Tuple{AbstractSerializer}, s)
end

function Serialization.serialize(s::RaySerializer, obj_ref::ObjectRef)
    push!(s.object_refs, obj_ref)

    owner_address, serialized_object_status = _get_ownership_info(obj_ref)

    invoke(serialize, Tuple{AbstractSerializer,ObjectRef}, s, obj_ref)

    # Append ownership information when serializing an `ObjectRef` with the `RaySerializer`.
    # This information will be deserialized another worker process and used during object
    # reference registration.
    serialize(s, owner_address)
    serialize(s, String(serialized_object_status))

    return nothing
end

function Serialization.deserialize(s::RaySerializer, T::Type{ObjectRef})
    obj_ref = invoke(deserialize, Tuple{AbstractSerializer,Type{ObjectRef}}, s, T)

    owner_address = deserialize(s)
    serialized_object_status = deserialize(s)
    s.object_owner[obj_ref] = OwnershipInfo(owner_address, serialized_object_status)

    push!(s.object_refs, obj_ref)

    return obj_ref
end

# As we are just throwing away the Serializer we can just avoid collecting the inlined
# object references
function serialize_to_bytes(x)
    bytes = Vector{UInt8}()
    io = IOBuffer(bytes; write=true)
    s = Serializer(io)
    writeheader(s)
    serialize(s, x)
    return bytes
end

function serialize_to_ray_object(data, metadata=nothing)
    bytes = Vector{UInt8}()
    s = RaySerializer(bytes)
    writeheader(s)
    serialize(s, data)
    data_buf = ray_jll.LocalMemoryBuffer(bytes, sizeof(bytes), true)

    metadata_buf = if !isnothing(metadata)
        ray_jll.LocalMemoryBuffer(Ptr{Nothing}(pointer(metadata)), sizeof(metadata), true)
    else
        ray_jll.NullPtr(ray_jll.Buffer)
    end

    inlined_ids = StdVector{ray_jll.ObjectID}(collect(s.object_ids))
    worker = ray_jll.GetCoreWorker()
    inlined_refs = ray_jll.GetObjectRefs(worker, inlined_ids)

    # This is actually a `SharedPtr{RayObject}`
    return ray_jll.RayObject(data_buf, metadata_buf, inlined_refs, false)
end

deserialize_from_bytes(bytes::Vector{UInt8}) = deserialize(Serializer(IOBuffer(bytes)))

# put this behind a function barrier so we're not generating the log message for
# huge objects
function log_deserialize_error(bytes, obj_ref=nothing)
    from = isnothing(obj_ref) ? "" : "`$(repr(obj_ref))` "
    @error "Unable to deserialize $(from)bytes: $(bytes2hex(bytes))"
end

function deserialize_from_ray_object(ray_obj::SharedPtr{ray_jll.RayObject},
                                     outer_object_ref=nothing)
    data = ray_jll.get_data(ray_obj)
    metadata = ray_jll.get_metadata(ray_obj)

    # If the raylet reports an error, metadata will be set to a numeric error code.
    if !isnothing(metadata)
        metadata = String(metadata)

        error_type = try
            parse(Int, metadata)
        catch e
            from = isnothing(outer_object_ref) ? "" : " from `$(repr(outer_object_ref))`"
            error("Encountered unhandled metadata$from: $metadata")
        end

        throw(RayError(error_type, data, outer_object_ref))
    end

    s = RaySerializer(IOBuffer(data))
    result = try
        deserialize(s)
    catch
        log_deserialize_error(data, outer_object_ref)
        rethrow()
    end

    for inner_object_ref in s.object_refs
        (; owner_address, serialized_object_status) = s.object_owner[inner_object_ref]
        _register_ownership(inner_object_ref, outer_object_ref, owner_address,
                            serialized_object_status)
    end

    # TODO: add an option to not rethrow
    # https://github.com/beacon-biosignals/Ray.jl/issues/58
    result isa RayError ? throw(result) : return result
end
