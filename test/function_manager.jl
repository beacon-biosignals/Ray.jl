@testset "function manager" begin
    using Ray: FUNCTION_MANAGER_NAMESPACE, FunctionManager, function_key, export_function!,
               import_function!
    using .ray_julia_jll: JuliaGcsClient, Connect, Disconnect, function_descriptor,
                          JuliaFunctionDescriptor, Exists

    client = JuliaGcsClient("127.0.0.1:6379")
    fm = FunctionManager(client, Dict{String,Any}())

    jobid = 1337

    f = x -> isless(x, 5)
    export_function!(fm, f, jobid)

    fd = function_descriptor(f)
    key = function_key(fd, jobid)
    @test ray_jll.Exists(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE, key)
    f2 = import_function!(fm, fd, jobid)

    @test f2.(1:10) == f.(1:10)

    mfd = function_descriptor(MyMod.f)
    @test_throws ErrorException import_function!(fm, mfd, jobid)
    mkey = function_key(mfd, jobid)
    @test !(ray_jll.Exists(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE, mkey))
    export_function!(fm, MyMod.f, jobid)

    # can import the function even when it's aliased in another module:
    nfd = function_descriptor(NotMyMod.f)
    @test mfd.function_hash == nfd.function_hash
    mf2 = import_function!(fm, nfd, jobid)
    @test MyMod.f.(1:10) == mf2.(1:10)

    mmfd = function_descriptor(MyMod.MySubMod.f)
    @test mmfd.module_name == "Main.MyMod.MySubMod"
    @test mmfd.function_name == "f"
    @test mmfd.function_hash != mfd.function_hash

    export_function!(fm, MyMod.MySubMod.f, jobid)
    mmf2 = import_function!(fm, mmfd, jobid)
    @test mmf2.(1:10) == MyMod.MySubMod.f.(1:10) != MyMod.f.(1:10)

    fc = let
        xthresh = 3
        x -> isless(x, xthresh)
    end
    export_function!(fm, fc, jobid)

    fcd = function_descriptor(fc)
    fc2 = import_function!(fm, fcd, jobid)
    @test fc.(1:10) == fc2.(1:10) != f.(1:10)

    @testset "warn/error for large functions" begin
        # for some reason, using `let` to introduce local scope does not work
        # during test execution to generate a closure, even though it works
        # locally, so we use a factory instead:
        function bigfactory(size)
            x = rand(UInt8, size)
            return f(y) = y * sum(x)
        end
        bigf = bigfactory(Ray.FUNCTION_SIZE_WARN_THRESHOLD)
        @test_logs (:warn, r"very large") export_function!(fm, bigf, jobid)
        bigfd = function_descriptor(bigf)
        bigf2 = import_function!(fm, bigfd, jobid)
        @test bigf(100) == bigf2(100)

        biggerf = bigfactory(Ray.FUNCTION_SIZE_ERROR_THRESHOLD)
        @test_throws ArgumentError export_function!(fm, biggerf, jobid)
    end

    # XXX: this works when run in global scope but unfortunately something about
    # the scope introduced by `@testset` causes the thunk sent as part of
    # `remotecall_fetch` to include refs to the modules defined in runtests.jl,
    # functions defined above, etc., that make it fail to deserialize (for
    # reasons that are completely unrelated to the actual functionality being
    # tested).

    # using Distributed
    # try
    #     worker = only(addprocs(1; exeflags="--project"))
    #     Distributed.remotecall_eval(Main, worker, quote
    #         using Pkg
    #         Pkg.activate($(Pkg.project().path))
    #         using Ray: FunctionManager, export_function!, import_function!
    #         using ray_julia_jll: JuliaGcsClient, Connect, function_descriptor
    #     end)
    #     # XXX: function descriptor does not serialize well, probalby since it's a
    #     # pointer under the hood.  I don't expect that this actually will matter for
    #     # us in practice (that's why we're using Ray!) but good to be aware.
    #     results = remotecall_fetch(worker, String(fd.function_hash), jobid) do function_hash, jobid
    #         client = JuliaGcsClient("127.0.0.1:6379")
    #         Connect(client)
    #         fm = FunctionManager(client, Dict{String,Any}())
    #         # currently only function hash is being used to lookup functions
    #         fd = function_descriptor("", "", function_hash)
    #         f = import_function!(fm, fd, jobid)
    #         # TODO: should we be doing this wrapping for _all_ remote functions?
    #         ff = (args...) -> invokelatest(f, args...)
    #         return ff.(1:10)
    #     end
    #     @test results == f.(1:10)
    # finally
    #     rmprocs(workers())
    # end
end
