"""
    Ray.put(data) -> ObjectIDAllocated

Stores `data` in the object store and returns an object reference assigned to the value that
can used to retrieve the data with [`Ray.get`](@ref).
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
    Ray.get(object_ids::Union{AbstractVector, Tuple})

Retrieves the data associated with the (collection of) `object_id`(s) from the object store.
This method is blocking until the data is available in the local object store.
"""
function get(oid::rayjll.ObjectIDAllocated)
    io = IOBuffer(take!(rayjll.get(oid)))
    return deserialize(io)
end

get(oids::Union{AbstractVector, Tuple}) = map(get, oids)
get(x) = x
