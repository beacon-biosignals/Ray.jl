struct ObjectRef
    oid::ray_jll.ObjectIDAllocated
end

ObjectRef(hex_str::AbstractString) = ObjectRef(ray_jll.FromHex(hex_str))
Base.string(obj_ref::ObjectRef) = String(ray_jll.Hex(obj_ref.oid))
Base.:(==)(a::ObjectRef, b::ObjectRef) = string(a) == string(b)

function Base.show(io::IO, obj_ref::ObjectRef)
    write(io, "ObjectRef(\"", string(obj_ref), "\")")
    return nothing
end

# We cannot serialize pointers between processes
function Serialization.serialize(s::AbstractSerializer, obj_ref::ObjectRef)
    serialize_type(s, typeof(obj_ref))
    serialize(s, string(obj_ref))
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{ObjectRef})
    hex_str = deserialize(s)
    return ObjectRef(hex_str)
end
