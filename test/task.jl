@testset "Submit task" begin
    # single argument
    result = submit_task(length, ("hello",))
    @test result isa ObjectRef
    @test Ray.get(result) isa Int
    @test Ray.get(result) == 5

    # multiple arguments
    result = submit_task(max, (0x00, 0xff))
    @test result isa ObjectRef
    @test Ray.get(result) isa UInt8
    @test Ray.get(result) == 0xff

    # no arguments
    result = submit_task(getpid, ())
    @test result isa ObjectRef
    @test Ray.get(result) isa Int32
    @test Ray.get(result) > getpid()

    # keyword arguments
    result = submit_task(sort, ([3, 1, 2],), (; rev=true))
    @test result isa ObjectRef
    @test Ray.get(result) isa Vector{Int}
    @test Ray.get(result) == [3, 2, 1]

    # error handling
    result = submit_task(error, ("AHHHHH",))
    @test result isa ObjectRef
    try
        Ray.get(result)
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

@testset "task runtime environment" begin
    @testset "project dir" begin
        # Project dir needs to include the current Ray.jl but have a different path than
        # the default
        project_dir = joinpath(Ray.project_dir(), "foo", "..")
        @test project_dir != Ray.RuntimeEnv().project

        f = () -> ENV["JULIA_PROJECT"]
        runtime_env = Ray.RuntimeEnv(; project=project_dir)
        result = Ray.get(submit_task(f, (); runtime_env))
        @test result == project_dir
    end

    @testset "package_imports" begin
        f = () -> nameof(Test)
        runtime_env = Ray.RuntimeEnv(; package_imports=:(using Test))
        result = Ray.get(submit_task(f, (); runtime_env))
        @test result == :Test

        # The spawned worker will fail with "ERROR: UndefVarError: `Test` not defined". We
        # can detect this failure attempting to fetch the task result.
        ref = submit_task(f, ())
        msg = if VERSION < v"1.9"
            "UndefVarError: Test not defined"
        else
            "UndefVarError: `Test` not defined"
        end
        @test_throws msg Ray.get(ref)
    end
end

@testset "job runtime environment" begin
    @testset "project dir" begin
        project_dir = @process_eval begin
            julia_project = () -> ENV["JULIA_PROJECT"]
            using Ray
            Ray.init()
            return Ray.get(submit_task(julia_project, ()))
        end

        @test project_dir == Ray.project_dir()
    end

    @testset "default loaded packages" begin
        worker_using = @process_eval begin
            # https://stackoverflow.com/a/63874246
            using_modules = function ()
                return nameof.(ccall(:jl_module_usings, Any, (Any,), Main)::Vector)
            end
            using Ray
            Ray.init()
            return Ray.get(submit_task(using_modules, ()))
        end

        @test :Ray in worker_using
    end

    @testset "@ray_import" begin
        # Excluding Ray and it's dependencies here only to make the test output cleaner
        driver_using, worker_using = @process_eval begin
            using_modules = function ()
                return nameof.(ccall(:jl_module_usings, Any, (Any,), Main)::Vector)
            end

            pre_using_modules = using_modules()
            @assert !(:Test in pre_using_modules)

            using Ray
            @ray_import begin
                using Test
            end
            driver_using = setdiff(using_modules(), pre_using_modules)
            Ray.init()
            worker_using = setdiff(Ray.get(submit_task(using_modules, ())), pre_using_modules)
            return driver_using, worker_using
        end

        @test :Test in driver_using
        @test :Test in worker_using
        @test driver_using == worker_using

        @testset "invalid use" begin
            msg = "`@ray_import` must be used before `Ray.init` and can only be called once"

            # `@ray_import` used after `Ray.init`
            ex = @process_eval begin
                using Ray
                Ray.init()
                try
                    @ray_import using Test
                    nothing
                catch e
                    e
                end
            end
            @test ex isa ErrorException
            @test ex.msg == msg

            # `@ray_import` used twice
            ex = @process_eval begin
                using Ray
                @ray_import using Test
                try
                    @ray_import using Test
                    nothing
                catch e
                    e
                end
            end
            @test ex isa ErrorException
            @test ex.msg == msg
        end

        # The evaluation of the expanded macro shouldn't require users to have imported the
        # `Ray` module into their module.
        @testset "non-import dependent" begin
            ray_defined = @process_eval begin
                import Ray as R
                R.@ray_import using Test
                isdefined(@__MODULE__, :Ray)
            end
            @test !ray_defined
        end
    end
end

@testset "many tasks" begin
    n_tasks = Sys.CPU_THREADS * 2
    # warm up worker cache pool
    pids = Ray.get.([submit_task(getpid, ()) for _ in 1:n_tasks])
    # run more tasks which should re-use the cpu cache
    pids2 = Ray.get.([submit_task(getpid, ()) for _ in 1:n_tasks])
    @test !isempty(intersect(pids, pids2))
end

# do this after the many tasks testset so we have workers warmed up
@testset "Async support for ObjectRef" begin
    obj_ref = submit_task(sleep, (3,))
    t = @async Ray.get(obj_ref)
    yield()

    # If C++ blocks then the task will complete prior to running these tests
    @test istaskstarted(t)
    @test !istaskdone(t)

    # If we don't wait for the task to complete and the task is still running after the
    # driver is shutdown we'll see the error: `ERROR: Package Ray errored during testing`
    # https://github.com/beacon-biosignals/Ray.jl/issues/96
    wait(t)
end

@testset "task resource requests" begin
    function gimme_resources()
        resources = ray_jll.get_task_required_resources()
        ks = ray_jll._keys(resources)
        return Dict(String(k) => float(ray_jll._getindex(resources, k)) for k in ks)
    end

    default_resources = Ray.get(submit_task(gimme_resources, ()))
    @test default_resources["CPU"] == 1.0

    custom_resources = Ray.get(submit_task(gimme_resources, (); resources=Dict("CPU" => 0.5)))
    @test custom_resources["CPU"] == 0.5
end
