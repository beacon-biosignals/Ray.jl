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

    # keyword arguments
    result = Ray.get(submit_task(sort, ([3, 1, 2],), (; rev=true)))
    @test result isa Vector{Int}
    @test result == [3, 2, 1]

    # error handling
    oid = submit_task(error, ("AHHHHH",))
    try
        Ray.get(oid)
    catch e
        @test e isa Ray.RayRemoteException
        @test e.captured.ex == ErrorException("AHHHHH")
    end
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
