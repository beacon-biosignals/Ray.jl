"""
    Ray.put(data) -> ObjectIDAllocated

Store `data` in the object store. Returns an object reference which can used to retrieve
the `data` with [`Ray.get`](@ref).
"""
function put(data)
    bytes = Vector{UInt8}()
    io = IOBuffer(bytes; write=true)
    serialize(io, data)
    buffer_ptr = Ptr{Nothing}(pointer(bytes))
    buffer_size = sizeof(bytes)
    buffer = rayjll.LocalMemoryBuffer(buffer_ptr, buffer_size, true)
    return rayjll.put(buffer)
end

"""
    Ray.get(object_id::ObjectIDAllocated)

Retrieves the data associated with the `object_id` from the object store.  This
method is blocking until the data is available in the local object store, even
if run in an `@async` task.

If the task that generated the `ObjectID` failed with a Julia exception, the
captured exception will be thrown on `get`.
"""
function get(oid::rayjll.ObjectIDAllocated)
    io = IOBuffer(take!(rayjll.get(oid)))
    result = deserialize(io)
    result isa RayRemoteException ? throw(result) : return result
end

get(x) = x
