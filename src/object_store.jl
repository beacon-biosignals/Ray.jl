"""
    Ray.put(data) -> ObjectRef

Store `data` in the object store. Returns an object reference which can used to retrieve
the `data` with [`Ray.get`](@ref).
"""
function put(data)
    ray_obj = serialize_to_ray_object(data)
    nested_ids = ray_jll.GetNestedRefIds(ray_obj[])

    # `CoreWorker::Put` initializes the local ref count to 1
    oid_ptr = CxxPtr(ray_jll.ObjectID())
    ray_jll.put(ray_obj, nested_ids, oid_ptr)
    return ObjectRef(oid_ptr[]; add_local_ref=false)
end

put(obj_ref::ObjectRef) = obj_ref

"""
    Ray.get(obj_ref::ObjectRef)

Retrieves the data associated with the object reference from the object store. This method
is blocking until the data is available in the local object store.

If the task that generated the `ObjectRef` failed with a Julia exception, the
captured exception will be thrown on `get`.
"""
function get(obj_ref::ObjectRef)
    wait(obj_ref)
    ray_objs = CxxPtr(StdVector{SharedPtr{ray_jll.RayObject}}())
    ray_jll.get(obj_ref.oid, 0, ray_objs)
    isnull(ray_objs) && error("got null pointer after successful `wait`; this is a bug!")
    return deserialize_from_ray_object(ray_objs[][1], obj_ref)
end

# get(ray_obj::SharedPtr{ray_jll.RayObject}) = deserialize_from_ray_object(ray_obj, nothing)

get(x) = x

"""
    Base.isready(obj_ref::ObjectRef)

Check whether `obj_ref` has a value that's ready to be retrieved.
"""
Base.isready(obj_ref::ObjectRef) = ray_jll.contains(obj_ref.oid)

"""
    Base.wait(obj_ref::ObjectRef) -> Nothing

Block until `isready(obj_ref)`.
"""
function Base.wait(obj_ref::ObjectRef)
    !has_owner(obj_ref) && error("Attempted to wait for unowned object: $obj_ref")
    while !isready(obj_ref)
        sleep(0.1)
    end
    return nothing
end

#####
##### Reference counting
#####

"""
    get_all_reference_counts()

For testing/debugging purposes, returns a
`Dict{ray_jll.ObjectID,Tuple{Int,Int}}` containing the reference counts for each
object ID that the local raylet knows about.  The first count is the "local
reference" count, and the second is the count of submitted tasks depending on
the object.
"""
function get_all_reference_counts()
    worker = ray_jll.GetCoreWorker()
    counts_raw = ray_jll.GetAllReferenceCounts(worker)

    # we need to convert this to a dict we can actually work with.  we use the
    # hex representation of the ID so we can avoid messing with the internal
    # ObjectID representation...
    counts = Dict(ray_jll.Hex(k) => Tuple(Int.(ray_jll._getindex(counts_raw, k)))
                  for k in ray_jll._keys(counts_raw))
    return counts
end
