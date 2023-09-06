"""
    Ray.put(data) -> ObjectIDAllocated

Store `data` in the object store. Returns an object reference which can used to retrieve
the `data` with [`Ray.get`](@ref).
"""
function put(data)
    bytes = serialize_to_bytes(data)
    buffer = ray_jll.LocalMemoryBuffer(bytes, sizeof(bytes), true)
    return ray_jll.put(buffer)
end

"""
    Ray.get(object_id::ObjectIDAllocated; timeout_ms=-1)

Retrieves the data associated with the `object_id` from the object store.  This
method is blocking until the data is available in the local object store, even
if run in an `@async` task.

If the task that generated the `ObjectID` failed with a Julia exception, the
captured exception will be thrown on `get`.
"""
get(oid::ray_jll.ObjectIDAllocated; timeout_ms::Int=-1) = _get(take!(ray_jll.get(oid, timeout_ms)))
get(obj::SharedPtr{ray_jll.RayObject}) = _get(take!(ray_jll.GetData(obj[])))
get(x) = x

function _get(bytes)
    result = deserialize_from_bytes(bytes)
    # TODO: add an option to not rethrow
    # https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl/issues/58
    result isa RayRemoteException ? throw(result) : return result
end

function serialize_to_bytes(x)
    bytes = Vector{UInt8}()
    io = IOBuffer(bytes; write=true)
    serialize(io, x)
    return bytes
end

deserialize_from_bytes(bytes) = deserialize(IOBuffer(bytes))
deserialize_from_bytes(::Nothing) = nothing
