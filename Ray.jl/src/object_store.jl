"""
    Ray.put(data) -> ObjectIDAllocated

Store `data` in the object store. Returns an object reference which can used to retrieve
the `data` with [`Ray.get`](@ref).
"""
function put(data)
    buffer = _put(data)
    return rayjll.put(buffer)
end

function _put(data)
    bytes = Vector{UInt8}()
    io = IOBuffer(bytes; write=true)
    serialize(io, data)
    return rayjll.LocalMemoryBuffer(bytes, sizeof(bytes), true)
end

"""
    Ray.get(object_id::ObjectIDAllocated)

Retrieves the data associated with the `object_id` from the object store.  This
method is blocking until the data is available in the local object store, even
if run in an `@async` task.

If the task that generated the `ObjectID` failed with a Julia exception, the
captured exception will be thrown on `get`.
"""
get(oid::rayjll.ObjectIDAllocated) = _get(take!(rayjll.get(oid)))
get(obj::SharedPtr{rayjll.RayObject}) = _get(take!(rayjll.GetData(obj[])))
get(x) = x

function _get(data::Vector{UInt8})
    result = deserialize(IOBuffer(data))
    # TODO: add an option to not rethrow
    result isa RayRemoteException ? throw(result) : return result
end
