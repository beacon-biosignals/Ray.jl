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
function log_deserialize_error(bytes)
    @error "Unable to deserialize $outer_object_ref bytes: $(bytes2hex(bytes))"
end

function deserialize_from_ray_object(x::SharedPtr{ray_jll.RayObject},
                                     outer_object_ref=nothing)
    # unlike CoreWorker::GetData, CoreWorker::GetMetadata returns a _reference_
    # to a pointer to a buffer, so we need to dereference the return value to
    # get the pointer that `take!` expects.
    metadata_ptr = ray_jll.GetMetadata(x[])[]
    # the pointer itself will not be null, but rather point to a null ref
    if !isnull(metadata_ptr[])
        metadata_bytes = take!(metadata_ptr)
        if !isempty(metadata_bytes)
            @warn "Unhandled RayObject.Metadata: $(String(metadata_bytes))"
        end
    end

    bytes = take!(ray_jll.GetData(x[]))
    s = RaySerializer(IOBuffer(bytes))
    result = try
        deserialize(s)
    catch
        log_deserialize_error(bytes)
        rethrow()
    end

    for inner_object_ref in s.object_refs
        _register_ownership(inner_object_ref, outer_object_ref)
    end

    # TODO: add an option to not rethrow
    # https://github.com/beacon-biosignals/Ray.jl/issues/58
    result isa RayTaskException ? throw(result) : return result
end
