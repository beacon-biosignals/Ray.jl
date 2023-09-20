struct RayTaskException <: Exception
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
    print(io, "RayTaskException: $(ex.task_name) (pid=$(ex.pid), ip=$(ex.ip), task_id=$(ex.task_id))")
    if backtrace
        bt !== nothing && Base.show_backtrace(io, bt)
        println(io)
    end
    printstyled(io, "\nnested exception: ", color=Base.error_color())
    # TODO: `showerror(io::IO, ex::CapturedException)` should accept `backtrace` keyword
    showerror(io, ex.captured.ex, ex.captured.processed_bt; backtrace)
end
