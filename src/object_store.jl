"""
    Ray.put(data) -> ObjectRef

Store `data` in the object store. Returns an object reference which can used to retrieve
the `data` with [`Ray.get`](@ref).
"""
function put(data)
    bytes = serialize_to_bytes(data)
    buffer = ray_jll.LocalMemoryBuffer(bytes, sizeof(bytes), true)
    ray_obj = ray_jll.RayObject(buffer)
    # `CoreWorker::Put` initializes the local ref count to 1
    return ObjectRef(ray_jll.put(ray_obj, StdVector{ray_jll.ObjectID}());
                     add_local_ref=false)
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
    ray_obj = ray_jll.get(obj_ref.oid, 0)
    isnull(ray_obj[]) && error("got null pointer after successful `wait`; this is a bug!")

    bytes = take!(ray_jll.GetData(ray_obj[]))
    return _get(bytes, obj_ref)
end

function get(ray_obj::SharedPtr{ray_jll.RayObject})
    bytes = take!(ray_jll.GetData(ray_obj[]))
    return _get(bytes, nothing)
end

get(x) = x

function _get(bytes::Vector{UInt8}, outer_obj_ref::Union{ObjectRef,Nothing})
    serializer = RaySerializer(IOBuffer(bytes))

    result = try
        deserialize(serializer)
    catch
        @error "Unable to deserialize $outer_obj_ref bytes: $(bytes2hex(bytes))"
        rethrow()
    end

    # TODO: This is disabled while we investigate how to implement properly
    # https://github.com/beacon-biosignals/Ray.jl/issues/77#issuecomment-1717675779
    # for obj_ref in serializer.object_refs
    #     _register_ownership(obj_ref, outer_obj_ref)
    # end

    # TODO: add an option to not rethrow
    # https://github.com/beacon-biosignals/Ray.jl/issues/58
    result isa RayRemoteException ? throw(result) : return result
end

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
