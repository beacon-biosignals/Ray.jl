function put(data)
    bytes = Vector{UInt8}()
    io = IOBuffer(bytes; write=true)
    serialize(io, data)
    buffer_ptr = Ptr{Nothing}(pointer(bytes))
    buffer_size = sizeof(bytes)
    buffer = rayjll.LocalMemoryBuffer(buffer_ptr, buffer_size, true)
    return rayjll.put(buffer)
end

function get(oid::rayjll.ObjectIDAllocated)
    io = IOBuffer(take!(rayjll.get(oid)))
    return deserialize(io)
end
