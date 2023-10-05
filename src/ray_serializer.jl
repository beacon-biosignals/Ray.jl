mutable struct RaySerializer{I<:IO} <: AbstractSerializer
    # Fields required by all AbstractSerializers
    io::I
    counter::Int
    table::IdDict{Any,Any}
    pending_refs::Vector{Int}
    version::Int

    # Inlined object references encountered during serializing
    object_refs::Set{ObjectRef}

    function RaySerializer{I}(io::I) where {I<:IO}
        return new(io, 0, IdDict(), Int[], Serialization.ser_version, Set{ObjectRef}())
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
    return invoke(serialize, Tuple{AbstractSerializer,ObjectRef}, s, obj_ref)
end

function Serialization.deserialize(s::RaySerializer, T::Type{ObjectRef})
    obj_ref = invoke(deserialize, Tuple{AbstractSerializer,Type{ObjectRef}}, s, T)
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

function serialize_to_ray_object(x)
    bytes = Vector{UInt8}()
    s = RaySerializer(bytes)
    writeheader(s)
    serialize(s, x)

    buffer = ray_jll.LocalMemoryBuffer(bytes, sizeof(bytes), true)
    metadata = ray_jll.NullPtr(ray_jll.Buffer)
    inlined_ids = StdVector(collect(s.object_ids))::StdVector{ray_jll.ObjectID}
    worker = ray_jll.GetCoreWorker()
    inlined_refs = ray_jll.GetObjectRefs(worker, inlined_ids)

    # this is actually a `std::shared_pointer<RayObject>`
    return ray_jll.RayObject(buffer, metadata, inlined_refs, false)
end

deserialize_from_bytes(bytes::Vector{UInt8}) = deserialize(Serializer(IOBuffer(bytes)))

# put this behind a function barrier so we're not generating the log message for
# huge objects
function log_deserialize_error(descriptor, data::Vector{UInt8}, outer_object_ref)
    obj_ref_str = isnothing(outer_object_ref) ? "" : "`$(repr(outer_object_ref))` "
    @error "Unable to deserialize $obj_ref_str$descriptor containing hex bytes: $(bytes2hex(data))"
end

function log_deserialize_error(descriptor, data, outer_object_ref)
    obj_ref_str = isnothing(outer_object_ref) ? "" : "`$(repr(outer_object_ref))` "
    @error "Unable to deserialize $obj_ref_str$descriptor: $(repr(data))"
end

function deserialize_from_ray_object(ray_obj::SharedPtr{ray_jll.RayObject},
                                     outer_object_ref=nothing)

    data, metadata = get_data_metadata(ray_obj)

    # TODO: Always include metadata and throw an exception if it is missing
    # The metadata specifies how the data should be deserialized or indicates an error
    # reported from the raylet.
    if !isnothing(metadata)
        # Return an exception based upon the error type
        error_type = try
            parse(Int, metadata)
        catch e
            log_deserialize_error("metadata", metadata, outer_object_ref)
            rethrow()
        end

        throw(RayException(error_type, data))
    elseif isnothing(data)
        throw(ArgumentError("object without metadata should always have data"))
    end

    s = RaySerializer(IOBuffer(data))
    result = try
        deserialize(s)
    catch
        log_deserialize_error("data", data, outer_object_ref)
        rethrow()
    end

    for inner_object_ref in s.object_refs
        _register_ownership(inner_object_ref, outer_object_ref)
    end

    # TODO: add an option to not rethrow
    # https://github.com/beacon-biosignals/Ray.jl/issues/58
    result isa RayException ? throw(result) : return result
end
