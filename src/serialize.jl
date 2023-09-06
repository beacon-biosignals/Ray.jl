using Serialization: Serializer, writeheader, serialize

mutable struct RaySerializer{I<:IO} <: AbstractSerializer
    io::I
    counter::Int
    table::IdDict{Any,Any}
    pending_refs::Vector{Int}

    object_refs::Set{ObjectRef}

    function RaySerializer{I}(io::I) where I<:IO
        return new(io, 0, IdDict(), Int[], Set{ObjectRef}())
    end
end

RaySerializer(io::IO) = RaySerializer{typeof(io)}(io)
RaySerializer(bytes::Vector{UInt8}) = RaySerializer{IOBuffer}(IOBuffer(bytes; write=true))

function Base.getproperty(s::RaySerializer, f::Symbol)
    if f === :object_ids
        return getproperty.(s.object_refs, :oid)
    else
        return getfield(s, f)
    end
end

function Serialization.serialize(s::RaySerializer, obj_ref::ObjectRef)
    push!(s.object_refs, obj_ref)
    return invoke(serialize, Tuple{AbstractSerializer, ObjectRef}, s, obj_ref)
end

# We cannot serialize pointers between processes
function Serialization.serialize(s::AbstractSerializer, obj_ref::ObjectRef)
    serialize_type(s, typeof(obj_ref))
    serialize(s, hex_identifier(obj_ref))
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{ObjectRef})
    hex_str = deserialize(s)
    return ObjectRef(hex_str)
end

function serialize_to_bytes(S::Type{<:AbstractSerializer}, x)
    bytes = Vector{UInt8}()
    io = IOBuffer(bytes; write=true)
    serialize(S(io), x)
    return bytes
end

function deserialize_from_bytes(S::Type{<:AbstractSerializer}, bytes)
    return deserialize(S(IOBuffer(bytes)))
end

serialize_to_bytes(x) = serialize_to_bytes(Serializer, x)
deserialize_from_bytes(bytes) = deserialize_from_bytes(Serializer, bytes)
