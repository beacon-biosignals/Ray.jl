@testset "Submit task" begin
    # single argument
    result = Ray.get(submit_task(length, ("hello",)))
    @test result isa Int
    @test result == 5

    # multiple arguments
    result = Ray.get(submit_task(max, (0x00, 0xff)))
    @test result isa UInt8
    @test result == 0xff

    # no arguments
    result = Ray.get(submit_task(getpid, ()))
    @test result isa Int32
    @test result > getpid()

    # error handling
    oid = submit_task(error, ("AHHHHH",))
    try
        Ray.get(oid)
    catch e
        @test e isa Ray.RayRemoteException
        @test e.captured.ex == ErrorException("AHHHHH")
    end
end

@testset "Task spawning a task" begin
    # As tasks may be run on the same worker it's better to use the task ID rather than the
    # process ID.
    f = function ()
        task_id = Ray.get_task_id()
        subtask_id = Ray.get(submit_task(Ray.get_task_id, ()))
        return (task_id, subtask_id)
    end

    task_id, subtask_id = Ray.get(submit_task(f, ()))
    @test Ray.get_task_id() != task_id != subtask_id
end

@testset "RuntimeEnv" begin
    @testset "project" begin
        # Project dir needs to include the current Ray.jl but have a different path than
        # the default
        project_dir = joinpath(Ray.project_dir(), "foo", "..")
        @test project_dir != Ray.RuntimeEnv().project

        f = () -> ENV["JULIA_PROJECT"]
        runtime_env = Ray.RuntimeEnv(; project=project_dir)
        result = Ray.get(submit_task(f, (); runtime_env))
        @test result == project_dir
    end
end
