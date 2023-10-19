# The exceptions defined here mostly mirror the exceptions supported by Ray for Python:
# https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/exceptions.py

struct ObjectContext
    object_ref_hex::String
    owner_address::ray_jll.Address
    call_site::String
end

function ObjectContext(obj_ref::ObjectRef)
    return ObjectContext(hex_identifier(obj_ref), get_owner_address(obj_ref), "")
end

ObjectContext(ctx::ObjectContext) = ctx

"""
    RayError <: Exception

Abstract super type of all Ray exception types.
"""
abstract type RayError <: Exception end

function RayError(error_type::Integer, data, obj::Union{ObjectRef,ObjectContext,Nothing})
    ex = if error_type == ray_jll.ErrorType(:WORKER_DIED)
        WorkerCrashedError()
    elseif error_type == ray_jll.ErrorType(:LOCAL_RAYLET_DIED)
        LocalRayletDiedError()
    elseif error_type == ray_jll.ErrorType(:TASK_CANCELLED)
        TaskCancelledError()
    elseif error_type == ray_jll.ErrorType(:OBJECT_LOST)
        ObjectLostError(ObjectContext(obj))
    elseif error_type == ray_jll.ErrorType(:OBJECT_FETCH_TIMED_OUT)
        ObjectFetchTimedOutError(ObjectContext(obj))
    elseif error_type == ray_jll.ErrorType(:OUT_OF_DISK_ERROR)
        OutOfDiskError(ObjectContext(obj))
    elseif error_type == ray_jll.ErrorType(:OUT_OF_MEMORY)
        OutOfMemoryError(deserialize_error_info(data))
    elseif error_type == ray_jll.ErrorType(:NODE_DIED)
        NodeDiedError(deserialize_error_info(data))
    else
        RaySystemError("Unrecognized error type $error_type")
    end

    return ex
end

# TODO: Exception data is actually serialized with a combination of MessagePack and Python
# pickle5. Luckily most of the useful information can be extracted with a basic heuristic.
function deserialize_error_info(data::AbstractString)
    first_index = findfirst(isletter, data)
    last_index = findlast(c -> isletter(c) | ispunct(c), data)
    return SubString(data, first_index, last_index)
end

deserialize_error_info(data::Vector{UInt8}) = deserialize_error_info(String(data))

function print_object_lost(io::IO, ctx::ObjectContext)
    print(io, "Failed to retrieve object $(ctx.object_ref_hex). ")

    # TODO: Support reporting call_site information
    # if !isempty(ex.call_site)
    #     print(io, "The `ObjectRef` was created at: $(ex.call_site)")
    # else
    #     print(io, "To see information about where this `ObjectRef` was created in Julia, " *
    #               "set the environment variable RAY_record_ref_creation_sites=1 during " *
    #               "`ray start` and `Ray.init()`.")
    # end
    # print(io, "\n\n")

    return nothing
end


"""
    RayTaskError <: RayError

Indicates that a Ray task threw an exception during execution.

If a Ray task throws an exception during execution, a `RayTaskError` is stored for the
Ray task's output. When the object is retrieved, the contained exception is detected and
thrown thereby propogating the exception to the Ray task caller.
"""
struct RayTaskError <: RayError
    task_name::String
    pid::Int
    ip::IPAddr
    task_id::String
    captured::CapturedException
end

function RayTaskError(task_name::AbstractString, captured::CapturedException)
    return RayTaskError(task_name, getpid(), getipaddr(), get_task_id(), captured)
end

function Base.showerror(io::IO, ex::RayTaskError, bt=nothing; backtrace=true)
    print(io, "$RayTaskError: $(ex.task_name) ")
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
    TaskCancelledError <: RayError

Raised when this task is cancelled.
"""
struct TaskCancelledError <: RayError end

function Base.showerror(io::IO, ex::TaskCancelledError)
    print(io, "$TaskCancelledError: This task or its dependency was cancelled")
    return nothing
end

"""
    LocalRayletDiedError <: RayError

Indicates that the task's local raylet died.
"""
struct LocalRayletDiedError <: RayError end

function Base.showerror(io::IO, ::LocalRayletDiedError)
    print(io, "$LocalRayletDiedError: The task's local raylet died. Check raylet.out for " *
              "more information.")
    return nothing
end

"""
    WorkerCrashedError <: RayError

Indicates that the worker died unexpectedly while executing a task.
"""
struct WorkerCrashedError <: RayError end

function Base.showerror(io::IO, ::WorkerCrashedError)
    print(io, "$WorkerCrashedError: The worker died unexpectedly while executing this " *
              "task. Check julia-core-worker-*.log files for more information.")
    return nothing
end

"""
    OutOfDiskError <: RayError

Indicates that the local disk is full.

This is raised if the attempt to store the object fails because both the object store and
disk are full.
"""
struct OutOfDiskError <: RayError
    object_context::ObjectContext
end

function Base.showerror(io::IO, ex::OutOfDiskError)
    print(io, "$OutOfDiskError: ")
    show(io, ex.object_context)
    print(io, "\nThe local object store is full of objects that are still in scope and " *
              "cannot be evicted. Tip: Use the `ray memory` command to list active " *
              "objects in the cluster.")
    return nothing
end

"""
    OutOfMemoryError <: RayError

Indicates that the node is running out of memory and is close to full.

This exception is thrown when the node is low on memory and tasks or actors are being
evicted to free up memory.
"""
struct OutOfMemoryError <: RayError
    msg::String
end

function Base.showerror(io::IO, ex::OutOfMemoryError)
    print(io, "$OutOfMemoryError: $(ex.msg)")
    return nothing
end

"""
    NodeDiedError <: RayError

Indicates that the node is either dead or unreachable.
"""
struct NodeDiedError <: RayError
    msg::String
end

function Base.showerror(io::IO, ex::NodeDiedError)
    print(io, "$NodeDiedError: $(ex.msg)")
    return nothing
end

"""
    ObjectLostError <: RayError

Indicates that the object is lost from distributed memory, due to node failure or system
error.
"""
struct ObjectLostError <: RayError
    object_context::ObjectContext
end

function Base.showerror(io::IO, ex::ObjectLostError)
    print(io, "$ObjectLostError: ")
    print_object_lost(io, ex.object_context)
    print(io, "All copies of $(ex.object_context.object_ref_hex) have been lost due to " *
              "node failure. Check cluster logs (\"/tmp/ray/session_latest/logs\") for " *
              "more information about the failure.")

    return nothing
end

"""
    ObjectFetchTimedOutError <: RayError

Indicates that an object fetch timed out.
"""
struct ObjectFetchTimedOutError <: RayError
    object_context::ObjectContext
end

function Base.showerror(io::IO, ex::ObjectFetchTimedOutError)
    print(io, "$ObjectFetchTimedOutError: ")
    print_object_lost(io, ex.object_context)
    print(io, "Fetch for object $(ex.object_context.object_ref_hex) timed out because no " *
              "locations were found for the object. This may indicate a system-level bug.")

    return nothing
end

"""
    RaySystemError <: RayError

Indicates that Ray encountered a system error.

This exception is thrown when:
- The raylet is killed.
- Deserialization of a `ObjectRef` contains an unknown metadata error type.
"""
struct RaySystemError <: RayError
    msg::String
end

function Base.showerror(io::IO, ex::RaySystemError)
    print(io, "$RaySystemError: $(ex.msg)")
    return nothing
end
