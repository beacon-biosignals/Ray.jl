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
        @test e isa Ray.RayTaskException
        @test e.captured.ex == ErrorException("AHHHHH")
    end

    # passthrough object refs as arguments
    with_logger(ConsoleLogger(Logging.Debug)) do
        remote_ref = Ray.put(1)
        return_ref = Ray.submit_task(identity, (remote_ref,))
        @test return_ref != remote_ref
        @test Ray.get(return_ref) == remote_ref
        @test Ray.get(Ray.get(return_ref)) == 1
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

@testset "Local ref count: Task return object" begin
    obj = Ray.submit_task(getpid, ())
    oid = obj.oid_hex
    @test local_count(oid) == 1

    finalize(obj)
    yield()
    @test local_count(oid) == 0
end

@testset "Ref count: Task argument object ref" begin
    task_dep_count(o::ObjectRef) = task_dep_count(o.oid_hex)
    task_dep_count(oid_hex) = last(get(Ray.get_all_reference_counts(), oid_hex, 0))

    obj = Ray.put(1)
    # XXX: The "task dependency" ref count goes to 0 when the task is
    # complete; Ray tests use an actor task which can be triggered to
    # complete by sending a "signal" (via another task call) to avoid race
    # conditions.  Here we're just hoping that the following test runs
    # within ~3s.
    ret_obj = Ray.submit_task(x -> (sleep(3); Ray.get(x)), (obj,))
    @test !isready(ret_obj) && task_dep_count(obj) == 1
    wait(ret_obj)
    @test task_dep_count(obj) == 0
end

@testset "object ownership" begin
    @testset "unknown owner" begin
        invalid_ref = ObjectRef(ray_jll.FromRandom(ray_jll.ObjectID))
        @test !Ray.has_owner(invalid_ref)

        msg = "An application is trying to access a Ray object whose owner is unknown"
        @test_throws msg Ray.get_owner_address(invalid_ref)
    end

    @testset "driver get on worker put" begin
        return_ref = submit_task(Ray.put, (2,))
        remote_ref = Ray.get(return_ref)
        @test Ray.has_owner(return_ref)
        @test Ray.has_owner(remote_ref)

        # Convert address to string to compare
        return_ref_addr = ray_jll.MessageToJsonString(Ray.get_owner_address(return_ref))
        remote_ref_addr = ray_jll.MessageToJsonString(Ray.get_owner_address(remote_ref))
        @test return_ref_addr != remote_ref_addr
        @test remote_ref_addr == remote_ref.owner_address_json

        @test Ray.get(remote_ref) == 2
    end

    # TODO: When owner registration is enabled this test seems to corrupt other ObjectIDs
    # such that later tests return the wrong results.
    @testset "worker get on driver put" begin
        local_ref = Ray.put(3)
        # XXX: getting empty address ID string here:
        return_ref = Ray.submit_task(Ray.get, (local_ref,))
        @test return_ref != local_ref
        @test Ray.has_owner(return_ref)
        @test Ray.has_owner(local_ref)

        # TODO: When owner registration is enabled this causes tasks to be re-run due to
        # "lost objects"
        @test Ray.get(return_ref) == 3
        @test Ray.get(local_ref) == 3
    end

    # Attempts to resolve all remote references before returning the result to the driver
    @testset "worker get on worker put" begin
        f = function (x)
            local_ref = Ray.put(x)
            return_ref = Ray.submit_task(Ray.get, (local_ref,))
            return Ray.get(return_ref)
        end
        return_ref = Ray.submit_task(f, (4,))
        @test Ray.get(return_ref) == 4

        g = function (x)
            return_ref = Ray.submit_task(Ray.put, (x,))
            remote_ref = Ray.get(return_ref)
            return Ray.get(remote_ref)
        end
        return_ref = Ray.submit_task(g, (5,))
        @test Ray.get(return_ref) == 5
    end

    @testset "driver get on worker return" begin
        f = x -> Ray.submit_task(identity, (x,))
        return_ref = Ray.submit_task(f, (6,))
        inner_ref = Ray.get(return_ref)
        @test inner_ref isa ObjectRef
        @test Ray.get(inner_ref) == 6
    end
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
            worker_using = Ray.get(submit_task(using_modules, ()))
            worker_using = setdiff(worker_using, pre_using_modules)
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
@testset "Async support for ObjectRef: $f" for f in (Ray.get, Base.wait)
    obj_ref = submit_task(sleep, (3,))
    @test !isready(obj_ref)
    t = @async f(obj_ref)
    yield()

    # If C++ blocks then the task will complete prior to running these tests
    @test istaskstarted(t)
    @test !istaskdone(t)

    # If we don't wait for the task to complete and the task is still running after the
    # driver is shutdown we'll see the error: `ERROR: Package Ray errored during testing`
    # https://github.com/beacon-biosignals/Ray.jl/issues/96
    wait(t)

    @test isready(obj_ref)
end

@testset "task resource requests" begin
    function gimme_resources()
        resources = ray_jll.get_task_required_resources()
        ks = ray_jll._keys(resources)
        return Dict(String(k) => float(ray_jll._getindex(resources, k)) for k in ks)
    end

    default_resources = Ray.get(submit_task(gimme_resources, ()))
    @test default_resources["CPU"] == 1.0

    resources = Dict("CPU" => 0.5)
    custom_resources = Ray.get(submit_task(gimme_resources, (); resources))
    @test custom_resources["CPU"] == 0.5
end
