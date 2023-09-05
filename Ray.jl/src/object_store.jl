"""
    Ray.put(data) -> ObjectRef

Store `data` in the object store. Returns an object reference which can used to retrieve
the `data` with [`Ray.get`](@ref).
"""
put(data) = ObjectRef(ray_jll.put(to_serialized_buffer(data)))
put(obj_ref::ObjectRef) = obj_ref

"""
    Ray.get(object_id::ObjectIDAllocated)

Retrieves the data associated with the `object_id` from the object store.  This
method is blocking until the data is available in the local object store, even
if run in an `@async` task.

If the task that generated the `ObjectID` failed with a Julia exception, the
captured exception will be thrown on `get`.
"""
get(obj_ref::ObjectRef) = _get(ray_jll.get(convert(ray_jll.ObjectID, obj_ref.oid)))
get(oid::ray_jll.ObjectIDAllocated) = _get(ray_jll.get(oid))
get(obj::SharedPtr{ray_jll.RayObject}) = _get(ray_jll.GetData(obj[]))
get(x) = x

function _get(buffer)
    result = from_serialized_buffer(buffer)
    # TODO: add an option to not rethrow
    # https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl/issues/58
    result isa RayRemoteException ? throw(result) : return result
end

function to_serialized_buffer(data)
    bytes = Vector{UInt8}()
    io = IOBuffer(bytes; write=true)
    serialize(io, data)
    return ray_jll.LocalMemoryBuffer(bytes, sizeof(bytes), true)
end

function from_serialized_buffer(buffer)
    result = deserialize(IOBuffer(take!(buffer)))
end
