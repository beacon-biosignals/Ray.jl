"""
    Ray.put(data) -> ObjectIDAllocated

Store `data` in the object store. Returns an object reference which can used to retrieve
the `data` with [`Ray.get`](@ref).
"""
function put(data)
    buffer = _put(data)
    return ray_jll.put(buffer)
end

function _put(data)
    bytes = Vector{UInt8}()
    io = IOBuffer(bytes; write=true)
    serialize(io, data)
    return ray_jll.LocalMemoryBuffer(bytes, sizeof(bytes), true)
end

"""
    Ray.get(object_id::ObjectIDAllocated)

Retrieves the data associated with the `object_id` from the object store.  This
method is blocking until the data is available in the local object store, even
if run in an `@async` task.

If the task that generated the `ObjectID` failed with a Julia exception, the
captured exception will be thrown on `get`.
"""
get(oid::ray_jll.ObjectIDAllocated) = _get(take!(ray_jll.get(oid)))
get(obj::SharedPtr{ray_jll.RayObject}) = _get(take!(ray_jll.GetData(obj[])))
get(x) = x

function _get(data::Vector{UInt8})
    result = deserialize(IOBuffer(data))
    # TODO: add an option to not rethrow
    # https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl/issues/58
    result isa RayRemoteException ? throw(result) : return result
end
