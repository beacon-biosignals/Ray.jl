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

        # The spawned worker will fail with "ERROR: UndefVarError: `Test` not defined". For
        # now since we have worker exception handling we'll detect this by attempting to
        # fetch the object.
        ref = submit_task(f, ())
        @test_throws "C++ object of type N3ray6BufferE was deleted" begin
            Ray.get(ref)
        end
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

    @testset "ray_import" begin
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
    end
end
