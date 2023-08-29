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
get(oid::rayjll.ObjectIDAllocated) = _get(take!(rayjll.get(oid)))
get(obj::SharedPtr{rayjll.RayObject}) = _get(take!(rayjll.GetData(obj[])))
get(x) = x

function _get(data::Vector{UInt8})
    result = deserialize(IOBuffer(data))
    # TODO: add an option to not rethrow
    # https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl/issues/58
    result isa RayRemoteException ? throw(result) : return result
end
