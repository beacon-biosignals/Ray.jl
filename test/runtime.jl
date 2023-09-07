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
        stderr_logs = String(take!(err))
        @test contains(stderr_logs, "Constructing CoreWorkerProcess")
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
        stderr_logs = String(take!(err))
        @test contains(stderr_logs, "Constructing CoreWorkerProcess")
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

@testset "serialize_args" begin
    ray_config = ray_jll.RayConfigInstance()
    put_threshold = ray_jll.max_direct_call_object_size(ray_config)
    rpc_inline_threshold = ray_jll.task_rpc_inlined_bytes_limit(ray_config)

    # The `flatten_args` function uses `:_` as the key for positional arguments.
    #
    # Note: We are indirectly testing that `serialize_args` and `serialize_to_bytes` both
    # match each other regarding including a serialization header. If there is a mismatch
    # then the tests below will fail.
    serialization_overhead = begin
        sizeof(Ray.serialize_to_bytes(:_ => zeros(UInt8, put_threshold))) - put_threshold
    end

    @testset "put threshold" begin
        a = :_ => zeros(UInt8, put_threshold - serialization_overhead)
        b = :_ => zeros(UInt8, put_threshold - serialization_overhead + 1)
        task_args = Ray.serialize_args([a, b])
        @test length(task_args) == 2
        @test task_args[1] isa ray_jll.TaskArgByValue
        @test task_args[2] isa ray_jll.TaskArgByReference
        map(UniquePtr ∘ CxxPtr , task_args)  # Add finalizer for memory cleanup

        task_args = Ray.serialize_args([b, a])
        @test length(task_args) == 2
        @test task_args[1] isa ray_jll.TaskArgByReference
        @test task_args[2] isa ray_jll.TaskArgByValue
        map(UniquePtr ∘ CxxPtr , task_args)  # Add finalizer for memory cleanup
    end

    @testset "inline threshold" begin
        a = :_ => zeros(UInt8, put_threshold - serialization_overhead)
        args = fill(a, rpc_inline_threshold ÷ put_threshold + 1)
        task_args = Ray.serialize_args(args)
        @test all(t -> t isa ray_jll.TaskArgByValue, task_args[1:(end - 1)])
        @test task_args[end] isa ray_jll.TaskArgByReference
        map(UniquePtr ∘ CxxPtr , task_args)  # Add finalizer for memory cleanup
    end
end

@testset "transform_task_args" begin
    task_args = Ray.serialize_args(Ray.flatten_args([1, 2, 3], (;)))
    result = Ray.transform_task_args(task_args)
    @test result isa StdVector{CxxPtr{ray_jll.TaskArg}}
    map(UniquePtr ∘ CxxPtr , task_args)  # Add finalizer for memory cleanup
end
