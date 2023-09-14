@testset "process_import_statements" begin
    @test Ray.process_import_statements(:(using Test)) == :(using Test)
    @test Ray.process_import_statements(:(using Test: @test)) == :(using Test: @test)
    @test Ray.process_import_statements(:(import Test)) == :(import Test)
    @test Ray.process_import_statements(:(import Test: @test)) == :(import Test: @test)
    @test Ray.process_import_statements(:(import Test as T)) == :(import Test as T)

    block = quote
        using Test
    end
    result = Ray.process_import_statements(block)
    @test result == Expr(:block, :(using Test))
    @test result != block  # LineNumberNode's have been stripped

    @test_throws ArgumentError Ray.process_import_statements(:(1 + 1))
    @test_throws ArgumentError Ray.process_import_statements(:(global foo = 1))
end

@testset "project_dir" begin
    result = Ray.project_dir()
    @test isdir(result)
    @test isabspath(result)
end

@testset "RuntimeEnv" begin
    @testset "defaults" begin
        runtime_env = RuntimeEnv()
        @test runtime_env.project == Ray.project_dir()
        @test runtime_env.package_imports == Expr(:block)
    end

    @testset "json_dict" begin
        project = "/tmp"
        package_imports = :(using Test)
        julia_command = [Base.julia_cmd().exec..., "-e", "using Ray; start_worker()"]

        runtime_env = Ray.RuntimeEnv(; project, package_imports)
        json = Ray.json_dict(runtime_env)

        @test json isa Dict
        @test keys(json) == Set(["julia_command", "env_vars"])
        @test json["julia_command"] isa Vector{String}
        @test json["julia_command"] == julia_command
        @test json["env_vars"] isa Dict{String,String}
        @test keys(json["env_vars"]) == Set(["JULIA_PROJECT", "JULIA_RAY_PACKAGE_IMPORTS"])
        @test json["env_vars"]["JULIA_PROJECT"] == project

        import_str = json["env_vars"]["JULIA_RAY_PACKAGE_IMPORTS"]
        result = deserialize(Base64DecodePipe(IOBuffer(import_str)))
        @test result == package_imports
    end
end
