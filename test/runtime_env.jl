@testset "process_import_statements" begin
    #! format: off
    @test Ray.process_import_statements(:(using Test)) == :(using Test)
    @test Ray.process_import_statements(:(using Test: @test)) == :(using Test: @test)
    @test Ray.process_import_statements(:(import Test)) == :(import Test)
    @test Ray.process_import_statements(:(import Test: @test)) == :(import Test: @test)
    @test Ray.process_import_statements(:(import Test as T)) == :(import Test as T)
    #! format: on

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
        runtime_env = Ray.RuntimeEnv()
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

@testset "JobConfig" begin
    @testset "defaults" begin
        @test_throws UndefKeywordError Ray.JobConfig()

        runtime_env_info = Ray.RuntimeEnvInfo(Ray.RuntimeEnv())
        job_config = Ray.JobConfig(; runtime_env_info)
        @test job_config.runtime_env_info isa Ray.RuntimeEnvInfo
        @test job_config.runtime_env_info == runtime_env_info
        @test job_config.metadata isa Dict{String,String}
        @test isempty(job_config.metadata)
    end

    @testset "json_dict" begin
        runtime_env_info = Ray.RuntimeEnvInfo(Ray.RuntimeEnv())
        metadata = Dict("job_submission_id" => "raysubmit_BzncEsVBi6uA3LA9",
                        "job_name" => "raysubmit_BzncEsVBi6uA3LA9")

        job_config = Ray.JobConfig(; runtime_env_info, metadata)
        json = Ray.json_dict(job_config)
        @test json["runtime_env_info"] == Ray.json_dict(runtime_env_info)
        @test json["metadata"] == metadata

        job_config = Ray.JobConfig(; runtime_env_info)
        json = Ray.json_dict(job_config)
        @test json["runtime_env_info"] == Ray.json_dict(runtime_env_info)
        @test !haskey(json, "metadata")
    end
end
