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

# Mirrors the functionality of the Python Ray function `get_owner_address`
# https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_raylet.pyx#L3308
function get_owner_address(obj_ref::ObjectRef)
    worker = ray_jll.GetCoreWorker()
    owner_address = ray_jll.Address()
    status = ray_jll.GetOwnerAddress(worker, obj_ref.oid, CxxPtr(owner_address))
    ray_jll.check_status(status)
    return owner_address
end

# TODO: A more efficiently `CoreWorker::HasOwner` exists but is private
function has_owner(obj_ref::ObjectRef)
    worker = ray_jll.GetCoreWorker()
    owner_address = ray_jll.Address()
    status = ray_jll.GetOwnerAddress(worker, obj_ref.oid, CxxPtr(owner_address))
    return !isempty(ray_jll.SerializeAsString(owner_address))
end

# We cannot serialize pointers between processes
function Serialization.serialize(s::AbstractSerializer, obj_ref::ObjectRef)
    worker = ray_jll.GetCoreWorker()

    owner_address = ray_jll.Address()
    serialized_object_status = StdString()
    ray_jll.GetOwnershipInfo(worker, obj_ref.oid, CxxPtr(owner_address), CxxPtr(serialized_object_status))
    owner_address_str = String(ray_jll.SerializeAsString(owner_address))
    serialized_object_status = String(serialized_object_status)

    serialize_type(s, typeof(obj_ref))
    serialize(s, hex_identifier(obj_ref))
    serialize(s, owner_address_str)
    serialize(s, serialized_object_status)

    return nothing
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{ObjectRef})
    worker = ray_jll.GetCoreWorker()

    hex_str = deserialize(s)
    owner_address_str = deserialize(s)
    serialized_object_status = deserialize(s)

    obj_ref = ObjectRef(hex_str)

    if !has_owner(obj_ref) && !isempty(owner_address_str)
        outer_object_id = ray_jll.Nil(ray_jll.ObjectID)
        owner_address = ray_jll.Address()
        ray_jll.ParseFromString(owner_address, owner_address_str)

        # https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_raylet.pyx#L3329
        # https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/core_worker.h#L543
        ray_jll.RegisterOwnershipInfoAndResolveFuture(worker, obj_ref.oid, outer_object_id,
                                                      owner_address, serialized_object_status)
    end

    return obj_ref
end
