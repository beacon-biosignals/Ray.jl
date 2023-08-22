@testset "Submit task" begin
    oid1 = submit_task(length, ("hello",))
    oid2 = submit_task(max, (0x00, 0xff))

    result1 = deserialize(IOBuffer(take!(ray_core_worker_julia_jll.get(oid1))))
    @test result1 isa Int
    @test result1 == 5

    result2 = deserialize(IOBuffer(take!(ray_core_worker_julia_jll.get(oid2))))
    @test result2 isa UInt8
    @test result2 == 0xff

    # task with no args
    oid3 = submit_task(getpid, ())
    result3 = deserialize(IOBuffer(take!(ray_core_worker_julia_jll.get(oid3))))
    @test result3 isa Int32
    @test result3 != getpid()
end

@testset "Task RuntimeEnv" begin
    @testset "project" begin
        # Project dir needs to include the current Ray.jl but have a different path than
        # the default
        project_dir = joinpath(Ray.project_dir(), "foo", "..")
        @test project_dir != Ray.RuntimeEnv().project

        f = () -> ENV["JULIA_PROJECT"]
        runtime_env = Ray.RuntimeEnv(; project=project_dir)
        oid = submit_task(f, (); runtime_env)
        result = deserialize(IOBuffer(take!(ray_core_worker_julia_jll.get(oid))))
        @test result == project_dir
    end

    @testset "package_imports" begin
        f = () -> nameof(Test)
        runtime_env = Ray.RuntimeEnv(; package_imports=:(using Test))
        oid = submit_task(f, (); runtime_env)
        result = deserialize(IOBuffer(take!(ray_core_worker_julia_jll.get(oid))))
        @test result == :Test

        # The spawned worker will fail with "ERROR: UndefVarError: `Test` not defined". For
        # now since we have worker exception handling we'll detect this by attempting to
        # fetch the object.
        oid = submit_task(f, ())
        @test_throws "C++ object of type N3ray6BufferE was deleted" begin
            take!(ray_core_worker_julia_jll.get(oid))
        end
    end
end
