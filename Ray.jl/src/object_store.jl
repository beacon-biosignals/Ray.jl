"""
    Ray.put(data) -> ObjectRef

Store `data` in the object store. Returns an object reference which can used to retrieve
the `data` with [`Ray.get`](@ref).
"""
function put(data)
    bytes = serialize_to_bytes(data)
    buffer = ray_jll.LocalMemoryBuffer(bytes, sizeof(bytes), true)
    ray_obj = ray_jll.RayObject(buffer)
    return ObjectRef(ray_jll.put(ray_obj, StdVector{ray_jll.ObjectID}()))
end

put(obj_ref::ObjectRef) = obj_ref

"""
    Ray.get(object_id::ObjectIDAllocated)

Retrieves the data associated with the `object_id` from the object store.  This
method is blocking until the data is available in the local object store, even
if run in an `@async` task.

If the task that generated the `ObjectID` failed with a Julia exception, the
captured exception will be thrown on `get`.
"""
get(obj_ref::ObjectRef; pollint_seconds=0.1) = get(obj_ref.oid; pollint_seconds)

function get(oid::ray_jll.ObjectIDAllocated)
    local ray_obj
    while true
        ray_obj = ray_jll.get(oid, 0)
        isnull(ray_obj[]) ? sleep(0.1) : break
    end
    return get(ray_obj)
end

get(ray_obj::SharedPtr{ray_jll.RayObject}) = _get(take!(ray_jll.GetData(ray_obj[])))
get(x; kwargs...) = x

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
