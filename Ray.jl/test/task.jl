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
end



@testset "job runtime environment" begin
    @testset "Ray automatically loaded" begin
        modules = @process_eval begin
            loaded_modules = () -> nameof.(Base.loaded_modules_array())
            pre_loaded = loaded_modules()
            using Ray
            Ray.init()
            worker_loaded = Ray.get(submit_task(loaded_modules, ()))
            setdiff(worker_loaded, pre_loaded)
        end

        @test :Ray in modules
    end

    @testset "Ray automatically loaded" begin
        modules = @process_eval begin
            loaded_modules = () -> nameof.(Base.loaded_modules_array())
            using Ray
            # loaded = loaded_modules()
            @ray_import begin
                using Test
            end
            # Ray.init()
            # worker_loaded = Ray.get(submit_task(loaded_modules, ()))
            # setdiff(worker_loaded, loaded)
        end

        @test :Ray in modules
    end






            sub

        julia_project = () -> ENV["JULIA_PROJECT"]
        oid = submit_task(julia_project, ())


        julia_project
        runtime_env = Ray.RuntimeEnv(; project=project_dir)
        oid = submit_task(f, (); runtime_env)
        result = Ray.get(oid)
        @test result == project_dir
    end

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

    @testset "package_imports" begin
        f = () -> nameof(Test)
        runtime_env = Ray.RuntimeEnv(; package_imports=:(using Test))
        result = Ray.get(submit_task(f, (); runtime_env))
        @test result == :Test

        # The spawned worker will fail with "ERROR: UndefVarError: `Test` not defined". For
        # now since we have worker exception handling we'll detect this by attempting to
        # fetch the object.
        ref = submit_task(f, ())
        @test_throws "C++ object of type N3ray6BufferE was deleted" begin
            Ray.get(ref)
        end
    end
end


@testset "Task RuntimeEnv" begin
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

    @testset "package_imports" begin
        f = () -> nameof(Test)
        runtime_env = Ray.RuntimeEnv(; package_imports=:(using Test))
        result = Ray.get(submit_task(f, (); runtime_env))
        @test result == :Test

        # The spawned worker will fail with "ERROR: UndefVarError: `Test` not defined". For
        # now since we have worker exception handling we'll detect this by attempting to
        # fetch the object.
        ref = submit_task(f, ())
        @test_throws "C++ object of type N3ray6BufferE was deleted" begin
            Ray.get(ref)
        end
    end
end
