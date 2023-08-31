@testset "control logs_dir" begin
    @testset "default logs_dir" begin
        # we're running this after `init` has been called, so logs should exist already:
        logs = readdir("/tmp/ray/session_latest/logs"; join=true)
        @test any(contains("julia-core-driver"), logs)
    end

    @testset "custom logs_dir" begin
        mktempdir() do logs_dir
            cp("/tmp/ray/session_latest/logs/raylet.out", joinpath(logs_dir, "raylet.out"))
            code = quote
                using Ray
                Ray.init(; logs_dir=$logs_dir)
            end
            cmd = `$(Base.julia_cmd()) --project=$(Ray.project_dir()) -e $code`
            err = IOBuffer()
            run(pipeline(cmd; stderr=err))

            logfiles = readdir(logs_dir; join=true)
            @test count(contains("julia-core-driver"), logfiles) == 1

            logs = read(only(filter(contains("julia-core-driver"), logfiles)), String)
            @test !isempty(logs)
            @test contains(logs, "Constructing CoreWorkerProcess")

            stderr_logs = String(take!(err))
            @test !contains(stderr_logs, "Constructing CoreWorkerProcess")
        end
    end

    @testset "log to stderr" begin
        code = quote
            using Ray
            Ray.init(; logs_dir="")
        end
        cmd = `$(Base.julia_cmd()) --project=$(Ray.project_dir()) -e $code`
        out = IOBuffer()
        err = IOBuffer()
        run(pipeline(cmd; stdout=out, stderr=err))
        logs = String(take!(err))
        @test contains(logs, "Constructing CoreWorkerProcess")
    end

    @testset "log to stderr: env var" begin
        code = quote
            using Ray
            ENV[Ray.LOGGING_REDIRECT_STDERR_ENVIRONMENT_VARIABLE] = "1"
            Ray.init()
        end
        cmd = `$(Base.julia_cmd()) --project=$(Ray.project_dir()) -e $code`
        out = IOBuffer()
        err = IOBuffer()
        run(pipeline(cmd; stdout=out, stderr=err))
        logs = String(take!(err))
        @test contains(logs, "Constructing CoreWorkerProcess")
    end

    @testset "kwarg takes precedence over env var" begin
        mktempdir() do logs_dir
            code = quote
                using Ray
                ENV[Ray.LOGGING_REDIRECT_STDERR_ENVIRONMENT_VARIABLE] = "1"
                Ray.init(; logs_dir=$logs_dir)
            end
            cmd = `$(Base.julia_cmd()) --project=$(Ray.project_dir()) -e $code`
            out = IOBuffer()
            err = IOBuffer()
            run(pipeline(cmd; stdout=out, stderr=err))

            logfiles = readdir(logs_dir; join=true)
            @test count(contains("julia-core-driver"), logfiles) == 1

            logs = read(only(filter(contains("julia-core-driver"), logfiles)), String)
            @test !isempty(logs)
            @test contains(logs, "Constructing CoreWorkerProcess")

            stderr_logs = String(take!(err))
            @test !contains(stderr_logs, "Constructing CoreWorkerProcess")
        end
    end

end
