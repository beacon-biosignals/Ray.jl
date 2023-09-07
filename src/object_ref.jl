struct ObjectRef
    oid::ray_jll.ObjectIDAllocated
end

ObjectRef(hex_str::AbstractString) = ObjectRef(ray_jll.FromHex(ray_jll.ObjectID, hex_str))
hex_identifier(obj_ref::ObjectRef) = String(ray_jll.Hex(obj_ref.oid))
Base.:(==)(a::ObjectRef, b::ObjectRef) = hex_identifier(a) == hex_identifier(b)

function Base.hash(obj_ref::ObjectRef, h::UInt)
    h = hash(ObjectRef, h)
    h = hash(hex_identifier(obj_ref), h)
    return h
end

function Base.show(io::IO, obj_ref::ObjectRef)
    write(io, "ObjectRef(\"", hex_identifier(obj_ref), "\")")
    return nothing
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
