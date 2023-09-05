struct ObjectRef
    oid::ray_jll.ObjectIDAllocated
end

ObjectRef(hex_str::AbstractString) = ObjectRef(ray_jll.FromHex(ray_jll.ObjectID, hex_str))
Base.string(obj_ref::ObjectRef) = String(ray_jll.Hex(obj_ref.oid))
Base.:(==)(a::ObjectRef, b::ObjectRef) = string(a) == string(b)

function Base.show(io::IO, obj_ref::ObjectRef)
    write(io, "ObjectRef(\"", string(obj_ref), "\")")
    return nothing
end

Base.convert(::Type{ray_jll.ObjectID}, obj_ref::ObjectRef) = obj_ref.oid
