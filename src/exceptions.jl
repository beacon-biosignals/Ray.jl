"""
    RayException <: Exception

Abstract super type of all Ray exception types.
"""
abstract type RayException <: Exception end

function RayException(error_type::Int, data)
    ex = if error_type == ray_jll.ErrorType(:OUT_OF_MEMORY)
        # TODO: Deserialize messagepack data
        OutOfMemoryException(bytes2hex(data))
    else
        RaySystemException("Unrecognized error type $error_type")
    end

    return ex
end

struct RayTaskException <: RayException
    task_name::String
    pid::Int
    ip::IPAddr
    task_id::String
    captured::CapturedException
end

function RayTaskException(task_name::AbstractString, captured::CapturedException)
    return RayTaskException(task_name, getpid(), getipaddr(), get_task_id(), captured)
end

function Base.showerror(io::IO, ex::RayTaskException, bt=nothing; backtrace=true)
    print(io, "RayTaskException: $(ex.task_name) ")
    print(io, "(pid=$(ex.pid), ip=$(ex.ip), task_id=$(ex.task_id))")
    if backtrace
        bt !== nothing && Base.show_backtrace(io, bt)
        println(io)
    end
    printstyled(io, "\nnested exception: "; color=Base.error_color())
    # Call 3-argument `showerror` to allow specifying `backtrace`
    showerror(io, ex.captured.ex, ex.captured.processed_bt; backtrace)
    return nothing
end

"""
    OutOfMemoryException <: RayException

Indicates that the node is running out of memory and is close to full.

This exception is thrown when the node is low on memory and tasks or actors are being
evicted to free up memory.
"""
struct OutOfMemoryException <: RayException
    msg::String
end

function Base.showerror(io::IO, ex::OutOfMemoryException)
    println(io, "$OutOfMemoryException: $(ex.msg)")
    return nothing
end

"""
    RaySystemException <: RayException

Indicates that Ray encountered a system error.

This exception is thrown when:
- The raylet is killed.
- Deserialization of a `ObjectRef` contains an unknown metadata error type.
"""
struct RaySystemException <: RayException
    msg::String
end

function Base.showerror(io::IO, ex::RaySystemException)
    println(io, "$RaySystemException: $(ex.msg)")
    return nothing
end
