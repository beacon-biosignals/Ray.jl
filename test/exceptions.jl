@testset "RayTaskError" begin
    e = ErrorException("foo")
    e = RayTaskError("test2", 2, ip"127.0.0.1", "t2",
                     CapturedException(e, backtrace()))
    rte = RayTaskError("test1", 1, ip"127.0.0.1", "t1",
                       CapturedException(e, backtrace()))

    str = sprint(showerror, rte)
    #! format: off
    @test occursin(r"^\QRayTaskError: test1 (pid=1, ip=127.0.0.1, task_id=t1)\E"m, str)
    @test occursin(r"^\Qnested exception: RayTaskError: test2 (pid=2, ip=127.0.0.1, task_id=t2)\E"m, str)
    @test occursin(r"^\Qnested exception: foo\E"m, str)
    #! format: on

    structure_regex = r"""
        ^RayTaskError: test1[^\n]++

        nested exception: RayTaskError: test2[^\n]++
        Stacktrace:
          ([^\n]++\n?)+

        nested exception: foo
        Stacktrace:
          ([^\n]++\n?)+$"""s
    @test occursin(structure_regex, str)

    str = sprint(rte) do io, args...
        showerror(io, args...; backtrace=false)
        return nothing
    end
    #! format: off
    @test occursin(r"^\QRayTaskError: test1 (pid=1, ip=127.0.0.1, task_id=t1)\E"m, str)
    @test occursin(r"^\Qnested exception: RayTaskError: test2 (pid=2, ip=127.0.0.1, task_id=t2)\E"m, str)
    @test occursin(r"^\Qnested exception: foo\E"m, str)
    #! format: on

    structure_regex = r"""
        ^RayTaskError: test1[^\n]++
        nested exception: RayTaskError: test2[^\n]++
        nested exception: foo$"""s
    @test occursin(structure_regex, str)
end

@testset "TaskCancelledError" begin
    msg = sprint(showerror, TaskCancelledError())
    @test msg == "TaskCancelledError: This task or its dependency was cancelled"
end

@testset "LocalRayletDiedError" begin
    msg = sprint(showerror, LocalRayletDiedError())
    @test startswith(msg, "LocalRayletDiedError: The task's local raylet died")
end

@testset "WorkerCrashedError" begin
    msg = sprint(showerror, WorkerCrashedError())
    @test startswith(msg, "WorkerCrashedError: The worker died unexpectedly")
end

@testset "OutOfMemoryError" begin
    e = Ray.OutOfMemoryError("foo")
    @test sprint(showerror, e) == "Ray.OutOfMemoryError: foo"
end

@testset "ObjectLostError" begin
    hex_str = "f"^(2 * 28)
    call_site = ""
    msg = sprint(showerror, ObjectLostError(hex_str, call_site))
    @test startswith(msg, "ObjectLostError: Failed to retrieve object $hex_str")
    @test contains(msg, "All copies of")
end

@testset "RaySystemError" begin
    e = RaySystemError("foo")
    @test sprint(showerror, e) == "RaySystemError: foo"
end

@testset "deserialize_error_info" begin
    # Captured data bytes from an OUT_OF_MEMORY error
    data = "\xcd\t\x93\x90\f\x7f\0\0\x90\xc5\t\x90*\x8b\x13Task was killed due to the node running low on memory.\nMemory on the node (IP: 10.0.22.131, ID: 6416deba2a6076b39bac8f9e2a405e5699ba1edddccf9d7e32cbb9ed) where the task (task ID: f8fbd7e11d4841630de13f6d9a990c6f5cf47f6c02000000, name=v0_4_4.process_segment, pid=606, memory used=3.33GB) was running was 51.33GB / 54.00GB (0.950537), which exceeds the memory usage threshold of 0.95. Ray killed this worker (ID: ad3de5a37126424c0dbc38c9b757d413753be34304bf078c3d58247d) because it was the most recently scheduled task; to see more information about memory usage on this node, use `ray logs raylet.out -ip 10.0.22.131`. To see the logs of the worker, use `ray logs worker-ad3de5a37126424c0dbc38c9b757d413753be34304bf078c3d58247d*out -ip 10.0.22.131. Top 10 memory users:\nPID\tMEM(GB)\tCOMMAND\n590\t4.04\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n434\t4.02\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n163\t3.98\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n572\t3.50\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n591\t3.43\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n606\t3.33\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n159\t3.19\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n160\t3.15\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n161\t3.14\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n158\t2.87\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\nRefer to the documentation on how to address the out of memory issue: https://docs.ray.io/en/latest/ray-core/scheduling/ray-oom-prevention.html. Consider provisioning more memory on this node or reducing task parallelism by requesting more CPUs per task. Set max_retries to enable retry when the task crashes due to OOM. To adjust the kill threshold, set the environment variable `RAY_memory_usage_threshold` when starting Ray. To disable worker killing, set the environment variable `RAY_memory_monitor_refresh_ms` to zero.X\x16"
    msg = Ray.deserialize_error_info(Vector{UInt8}(data))
    @test startswith(msg, "Task was killed")
    @test endswith(msg, "environment variable `RAY_memory_monitor_refresh_ms` to zero.X")
end

@testset "RayError" begin
    hex_str = "f"^(2 * 28)
    obj_ref = ObjectRef(hex_str; add_local_ref=false)

    @test RayError(ray_jll.ErrorType(:WORKER_DIED), "", obj_ref) == WorkerCrashedError()
    @test RayError(ray_jll.ErrorType(:LOCAL_RAYLET_DIED), "", obj_ref) == LocalRayletDiedError()
    @test RayError(ray_jll.ErrorType(:TASK_CANCELLED), "", obj_ref) == TaskCancelledError()
    @test RayError(ray_jll.ErrorType(:OBJECT_LOST), "", obj_ref) == ObjectLostError(hex_str, "")
    @test RayError(ray_jll.ErrorType(:OUT_OF_MEMORY), "foo", obj_ref) == Ray.OutOfMemoryError("foo")
    @test RayError(-1, nothing, obj_ref) == RaySystemError("Unrecognized error type -1")
end
