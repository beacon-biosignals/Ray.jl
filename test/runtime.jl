@testset "control logs_dir" begin
    @testset "default logs_dir" begin
        # we're running this after `init` has been called, so logs should exist already:
        logs = readdir("/tmp/ray/session_latest/logs"; join=true)
        @test any(contains("julia-core-driver"), logs)
    end

    @testset "custom logs_dir" begin
        mktempdir() do logs_dir
            cp("/tmp/ray/session_latest/logs/raylet.out", joinpath(logs_dir, "raylet.out"))
            err = IOBuffer()
            code = quote
                using Ray
                Ray.init(; logs_dir=$logs_dir)
            end
            process_eval(code; stderr=err)

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
        err = IOBuffer()
        @process_eval stderr = err begin
            using Ray
            Ray.init(; logs_dir="")
        end

        stderr_logs = String(take!(err))
        @test contains(stderr_logs, "Constructing CoreWorkerProcess")
    end

    @testset "log to stderr: env var" begin
        err = IOBuffer()
        @process_eval stderr = err begin
            using Ray
            ENV[Ray.LOGGING_REDIRECT_STDERR_ENVIRONMENT_VARIABLE] = "1"
            Ray.init()
        end

        stderr_logs = String(take!(err))
        @test contains(stderr_logs, "Constructing CoreWorkerProcess")
    end

    @testset "kwarg takes precedence over env var" begin
        mktempdir() do logs_dir
            err = IOBuffer()
            code = quote
                using Ray
                ENV[Ray.LOGGING_REDIRECT_STDERR_ENVIRONMENT_VARIABLE] = "1"
                Ray.init(; logs_dir=$logs_dir)
            end
            process_eval(code; stderr=err)

            logfiles = readdir(logs_dir; join=true)
            @test count(contains("julia-core-driver"), logfiles) == 1

            logs = read(only(filter(contains("julia-core-driver"), logfiles)), String)
            @test !isempty(logs)
            @test contains(logs, "Constructing CoreWorkerProcess")

            stderr_logs = String(take!(err))
            @test !contains(stderr_logs, "Constructing CoreWorkerProcess")
        end
    end

    @testset "job config metadata" begin
        job_config_json = Dict(:metadata => Dict(:job_name => "test"))

        json_str = withenv("RAY_JOB_CONFIG_JSON_ENV_VAR" => JSON3.write(job_config_json)) do
            @process_eval begin
                using Ray, JSON3
                using Ray: ray_julia_jll
                Ray.init()
                worker = ray_julia_jll.GetCoreWorker()
                worker_context = ray_julia_jll.GetWorkerContext(worker)
                job_config = ray_julia_jll.GetCurrentJobConfig(worker_context)
                return String(ray_julia_jll.MessageToJsonString(job_config))
            end
        end

        result = JSON3.read(json_str)
        @test haskey(result, :metadata)
        @test result[:metadata] == job_config_json[:metadata]
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
        map(UniquePtr ∘ CxxPtr, task_args)  # Add finalizer for memory cleanup

        task_args = Ray.serialize_args([b, a])
        @test length(task_args) == 2
        @test task_args[1] isa ray_jll.TaskArgByReference
        @test task_args[2] isa ray_jll.TaskArgByValue
        map(UniquePtr ∘ CxxPtr, task_args)  # Add finalizer for memory cleanup
    end

    @testset "inline threshold" begin
        a = :_ => zeros(UInt8, put_threshold - serialization_overhead)
        args = fill(a, rpc_inline_threshold ÷ put_threshold + 1)
        task_args = Ray.serialize_args(args)
        @test all(t -> t isa ray_jll.TaskArgByValue, task_args[1:(end - 1)])
        @test task_args[end] isa ray_jll.TaskArgByReference
        map(UniquePtr ∘ CxxPtr, task_args)  # Add finalizer for memory cleanup
    end
end

@testset "transform_task_args" begin
    task_args = Ray.serialize_args(Ray.flatten_args([1, 2, 3], (;)))
    result = Ray.transform_task_args(task_args)
    @test result isa StdVector{CxxPtr{ray_jll.TaskArg}}
    map(UniquePtr ∘ CxxPtr, task_args)  # Add finalizer for memory cleanup
end
