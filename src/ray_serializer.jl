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

    inlined_ids = StdVector(collect(s.object_ids))::StdVector{ray_jll.ObjectID}
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

    metadata = ray_jll.get_metadata(ray_obj)
    if !isnothing(metadata)
        from = isnothing(outer_object_ref) ? "" : "from `$(repr(outer_object_ref))`"
        error("Encountered unhandled metadata$from: $(String(metadata))")
    end

    data = ray_jll.get_data(ray_obj)
    s = RaySerializer(IOBuffer(data))
    result = try
        deserialize(s)
    catch
        log_deserialize_error(data, outer_object_ref)
        rethrow()
    end

    for inner_object_ref in s.object_refs
        _register_ownership(inner_object_ref, outer_object_ref)
    end

    # TODO: add an option to not rethrow
    # https://github.com/beacon-biosignals/Ray.jl/issues/58
    result isa RayTaskException ? throw(result) : return result
end
