@testset "deserialize_error_info" begin
    @testset "OUT_OF_MEMORY" begin
        # Captured data bytes from an OUT_OF_MEMORY error
        data = "\xcd\t\x93\x90\f\x7f\0\0\x90\xc5\t\x90*\x8b\x13Task was killed due to the node running low on memory.\nMemory on the node (IP: 10.0.22.131, ID: 6416deba2a6076b39bac8f9e2a405e5699ba1edddccf9d7e32cbb9ed) where the task (task ID: f8fbd7e11d4841630de13f6d9a990c6f5cf47f6c02000000, name=v0_4_4.process_segment, pid=606, memory used=3.33GB) was running was 51.33GB / 54.00GB (0.950537), which exceeds the memory usage threshold of 0.95. Ray killed this worker (ID: ad3de5a37126424c0dbc38c9b757d413753be34304bf078c3d58247d) because it was the most recently scheduled task; to see more information about memory usage on this node, use `ray logs raylet.out -ip 10.0.22.131`. To see the logs of the worker, use `ray logs worker-ad3de5a37126424c0dbc38c9b757d413753be34304bf078c3d58247d*out -ip 10.0.22.131. Top 10 memory users:\nPID\tMEM(GB)\tCOMMAND\n590\t4.04\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n434\t4.02\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n163\t3.98\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n572\t3.50\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n591\t3.43\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n606\t3.33\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n159\t3.19\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n160\t3.15\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n161\t3.14\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\n158\t2.87\t/usr/local/julia/bin/julia -Cnative -J/usr/local/julia/lib/julia/sys.so -g1 -e using Ray; start_work...\nRefer to the documentation on how to address the out of memory issue: https://docs.ray.io/en/latest/ray-core/scheduling/ray-oom-prevention.html. Consider provisioning more memory on this node or reducing task parallelism by requesting more CPUs per task. Set max_retries to enable retry when the task crashes due to OOM. To adjust the kill threshold, set the environment variable `RAY_memory_usage_threshold` when starting Ray. To disable worker killing, set the environment variable `RAY_memory_monitor_refresh_ms` to zero.X\x16"
        msg = Ray.deserialize_error_info(Vector{UInt8}(data))
        @test startswith(msg, "Task was killed")
        @test endswith(msg, "variable `RAY_memory_monitor_refresh_ms` to zero.X")
    end
end

@testset "ActorPlacementGroupRemoved" begin
    msg = sprint(showerror, ActorPlacementGroupRemoved())
    expected = "ActorPlacementGroupRemoved: The placement group corresponding to this Actor has been removed."
    @test msg == expected
end

@testset "ActorUnschedulableError" begin
    msg = sprint(showerror, ActorUnschedulableError("foo\0"))
    @test msg == "ActorUnschedulableError: The actor is not schedulable: foo\0"
end

@testset "LocalRayletDiedError" begin
    msg = sprint(showerror, LocalRayletDiedError())
    @test startswith(msg, "LocalRayletDiedError: The task's local raylet died")
end

@testset "NodeDiedError" begin
    msg = sprint(showerror, NodeDiedError("foo\0"))
    @test msg == "NodeDiedError: foo\0"
end

@testset "ObjectFetchTimedOutError" begin
    obj_ctx = Ray.ObjectContext("f"^(2 * 28), ray_jll.Address(), "")
    e = ObjectFetchTimedOutError(obj_ctx)
    msg = sprint(showerror, e)
    @test startswith(msg, "ObjectFetchTimedOutError: Failed to retrieve object")
    @test contains(msg, "Fetch for object")
end

@testset "ObjectFreedError" begin
    obj_ctx = Ray.ObjectContext("f"^(2 * 28), ray_jll.Address(), "")
    e = ObjectFreedError(obj_ctx)
    msg = sprint(showerror, e)
    @test startswith(msg, "ObjectFreedError: Failed to retrieve object")
    @test contains(msg, "The object was manually freed")
end

@testset "ObjectLostError" begin
    obj_ctx = Ray.ObjectContext("f"^(2 * 28), ray_jll.Address(), "")
    e = ObjectLostError(obj_ctx)
    msg = sprint(showerror, e)
    @test startswith(msg, "ObjectLostError: Failed to retrieve object")
    @test contains(msg, "All copies of")
end

@testset "ObjectReconstructionFailedError" begin
    obj_ctx = Ray.ObjectContext("f"^(2 * 28), ray_jll.Address(), "")
    e = ObjectReconstructionFailedError(obj_ctx)
    msg = sprint(showerror, e)
    @test startswith(msg, "ObjectReconstructionFailedError: Failed to retrieve object")
    @test contains(msg, "The object cannot be reconstructed")
end

@testset "ObjectReconstructionFailedLineageEvictedError" begin
    obj_ctx = Ray.ObjectContext("f"^(2 * 28), ray_jll.Address(), "")
    e = ObjectReconstructionFailedLineageEvictedError(obj_ctx)
    msg = sprint(showerror, e)
    @test startswith(msg, "$(typeof(e)): Failed to retrieve object")
    @test contains(msg, "The object cannot be reconstructed because its lineage")
end

@testset "ObjectReconstructionFailedMaxAttemptsExceededError" begin
    obj_ctx = Ray.ObjectContext("f"^(2 * 28), ray_jll.Address(), "")
    e = ObjectReconstructionFailedMaxAttemptsExceededError(obj_ctx)
    msg = sprint(showerror, e)
    @test startswith(msg, "$(typeof(e)): Failed to retrieve object")
    @test contains(msg, "The object cannot be reconstructed because the maximum")
end

@testset "OutOfDiskError" begin
    obj_ctx = Ray.ObjectContext("f"^(2 * 28), ray_jll.Address(), "")
    e = OutOfDiskError(obj_ctx)
    msg = sprint(showerror, e)
    @test startswith(msg,
                     r"OutOfDiskError: (Ray\.)?ObjectContext\(.*?\)\n" *
                     "The local object store is full of objects")
end

@testset "OutOfMemoryError" begin
    e = Ray.OutOfMemoryError("foo\0")
    @test sprint(showerror, e) == "Ray.OutOfMemoryError: foo\0"
end

@testset "OwnerDiedError" begin
    obj_ctx = Ray.ObjectContext("f"^(2 * 28), ray_jll.Address(), "")
    msg = sprint(showerror, OwnerDiedError(obj_ctx))
    @test startswith(msg, "OwnerDiedError: Failed to retrieve object")
    @test contains(msg, "The object's owner has exited")
    @test contains(msg, "Check cluster logs (\"/tmp/ray/session_latest/logs\")")

    addr = ray_jll.Address((; raylet_id="a"^(2 * 28), worker_id="b"^(2 * 28),
                            ip_address="127.0.0.1", port=1000))
    obj_ctx = Ray.ObjectContext("f"^(2 * 28), addr, "")
    msg = sprint(showerror, OwnerDiedError(obj_ctx))
    @test startswith(msg, "OwnerDiedError: Failed to retrieve object")
    @test contains(msg, "The object's owner has exited")
    @test contains(msg,
                   "Check cluster logs (\"/tmp/ray/session_latest/logs/*" * r"b{56}" *
                   "*\" at IP address 127.0.0.1)")
end

@testset "RaySystemError" begin
    e = RaySystemError("foo\0")
    @test sprint(showerror, e) == "RaySystemError: foo\0"
end

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

@testset "ReferenceCountingAssertionError" begin
    obj_ctx = Ray.ObjectContext("f"^(2 * 28), ray_jll.Address(), "")
    msg = sprint(showerror, ReferenceCountingAssertionError(obj_ctx))
    @test startswith(msg, "ReferenceCountingAssertionError: Failed to retrieve object")
    @test contains(msg, "The object has already been deleted")
end

@testset "RuntimeEnvSetupError" begin
    msg = sprint(showerror, RuntimeEnvSetupError("foo\0"))
    @test msg == "RuntimeEnvSetupError: Failed to set up runtime environment.\nfoo\0"
end

@testset "TaskCancelledError" begin
    msg = sprint(showerror, TaskCancelledError())
    @test msg == "TaskCancelledError: This task or its dependency was cancelled"
end

@testset "TaskPlacementGroupRemoved" begin
    msg = sprint(showerror, TaskPlacementGroupRemoved())
    expected = "TaskPlacementGroupRemoved: The placement group corresponding to this task has been removed."
    @test msg == expected
end

@testset "TaskUnschedulableError" begin
    msg = sprint(showerror, TaskUnschedulableError("foo\0"))
    @test msg == "TaskUnschedulableError: The task is not schedulable: foo\0"
end

@testset "WorkerCrashedError" begin
    msg = sprint(showerror, WorkerCrashedError())
    @test startswith(msg, "WorkerCrashedError: The worker died unexpectedly")
end

@testset "RayError" begin
    # TODO: Should we test with `ObjectRef`? The `get_owner_address` call requires a worker context
    obj_ctx = Ray.ObjectContext("f"^(2 * 28), ray_jll.Address(), "")
    data = "foo\0"
    esc_data = "\"foo\\0\""

    RayError(sym::Symbol) = Ray.RayError(ray_jll.ErrorType(sym), data, obj_ctx)
    RayError(args...) = Ray.RayError(args...)

    @test RayError(:WORKER_DIED) == WorkerCrashedError()
    @test RayError(:LOCAL_RAYLET_DIED) == LocalRayletDiedError()
    @test RayError(:TASK_CANCELLED) == TaskCancelledError()
    @test RayError(:OBJECT_LOST) == ObjectLostError(obj_ctx)
    @test RayError(:OBJECT_FETCH_TIMED_OUT) == ObjectFetchTimedOutError(obj_ctx)
    @test RayError(:OUT_OF_DISK_ERROR) == OutOfDiskError(obj_ctx)
    @test RayError(:OUT_OF_MEMORY) == Ray.OutOfMemoryError("foo")
    @test RayError(:NODE_DIED) == NodeDiedError(esc_data)
    @test RayError(:OBJECT_DELETED) == ReferenceCountingAssertionError(obj_ctx)
    @test RayError(:OBJECT_FREED) == ObjectFreedError(obj_ctx)
    @test RayError(:OWNER_DIED) == OwnerDiedError(obj_ctx)
    @test RayError(:OBJECT_UNRECONSTRUCTABLE) == ObjectReconstructionFailedError(obj_ctx)
    @test RayError(:OBJECT_UNRECONSTRUCTABLE_MAX_ATTEMPTS_EXCEEDED) ==
          ObjectReconstructionFailedMaxAttemptsExceededError(obj_ctx)
    @test RayError(:OBJECT_UNRECONSTRUCTABLE_LINEAGE_EVICTED) ==
          ObjectReconstructionFailedLineageEvictedError(obj_ctx)
    @test RayError(:RUNTIME_ENV_SETUP_FAILED) == RuntimeEnvSetupError(esc_data)
    @test RayError(:TASK_PLACEMENT_GROUP_REMOVED) == TaskPlacementGroupRemoved()
    @test RayError(:ACTOR_PLACEMENT_GROUP_REMOVED) == ActorPlacementGroupRemoved()
    @test RayError(:TASK_UNSCHEDULABLE_ERROR) == TaskUnschedulableError(esc_data)
    @test RayError(:ACTOR_UNSCHEDULABLE_ERROR) == ActorUnschedulableError(esc_data)
    @test RayError(-1, nothing, obj_ctx) == RaySystemError("Unrecognized error type -1")
end
