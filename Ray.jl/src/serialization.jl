# We cannot serialize pointers between processes
function Serialization.serialize(s::AbstractSerializer, o::ray_jll.ObjectIDAllocated)
    serialize_type(s, typeof(o))
    serialize(s, String(ray_jll.Hex(o)))
end

function Serialization.deserialize(s::AbstractSerializer, t::Type{ray_jll.ObjectIDAllocated})
    hex_str = deserialize(s)
    return ray_jll.FromHex(hex_str)
end
