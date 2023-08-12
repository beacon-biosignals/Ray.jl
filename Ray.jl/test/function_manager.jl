@testset "function manager" begin
    using Distributed
    using Ray: FunctionManager, export_function!, import_function!
    using ray_core_worker_julia_jll: JuliaGcsClient, Connect, function_descriptor, JuliaFunctionDescriptor, Exists

    client = JuliaGcsClient("127.0.0.1:6379")
    Connect(client)

    fm = FunctionManager(client, Dict{String,Any}())

    jobid = 1337

    f = x -> isless(x, 5)
    export_function!(fm, f, jobid)

    # XXX: this will segfault since the pointer is released...
    fd = function_descriptor(f)
    f2 = import_function!(fm, fd, jobid)

    @test f2.(1:10) == f.(1:10)

    mfd = function_descriptor(M.f)
    @test_throws ErrorException import_function!(fm, mfd, jobid)
    export_function!(fm, M.f, jobid)

    # can import the function even when it's aliased in another module:
    nfd = function_descriptor(N.f)
    @test mfd.function_hash == nfd.function_hash
    mf2 = import_function!(fm, nfd, jobid)
    @test M.f.(1:10) == mf2.(1:10)

    mmfd = function_descriptor(M.MM.f)
    @test mmfd.module_name == "Main.M.MM"
    @test mmfd.function_name == "f"
    @test mmfd.function_hash != mfd.function_hash

    export_function!(fm, M.MM.f, jobid)
    mmf2 = import_function!(fm, mmfd, jobid)
    @test mmf2.(1:10) == M.MM.f.(1:10) != M.f.(1:10)

    fc = let
        xthresh = 3
        x -> isless(x, xthresh)
    end
    export_function!(fm, fc, jobid)

    fcd = function_descriptor(fc)
    fc2 = import_function!(fm, fcd, jobid)
    @test fc.(1:10) == fc2.(1:10) != f.(1:10)

    try
        worker = only(addprocs(1; exeflags="--project"))
        @everywhere worker begin
            using Pkg
            Pkg.activate($(Pkg.project().path))
        end

        @everywhere worker begin
            using Ray: FunctionManager, export_function!, import_function!
    using ray_core_worker_julia_jll: JuliaGcsClient, Connect, function_descriptor
        end

        # XXX: function descriptor does not serialize well, probalby since it's a
        # pointer under the hood.  I don't expect that this actually will matter for
        # us in practice (that's why we're using Ray!) but good to be aware.
        results = remotecall_fetch(worker, String(fd.function_hash), jobid) do function_hash, jobid
            client = JuliaGcsClient("127.0.0.1:6379")
            Connect(client)
            fm = FunctionManager(client, Dict{String,Any}())
            fd = function_descriptor("", "", function_hash)
            f = import_function!(fm, fd, jobid)
            # TODO: should we be doing this wrapping for _all_ remote functions?
            ff = (args...) -> invokelatest(f, args...)
            return ff.(1:10)
        end
        @test results == f.(1:10)
    finally
        rmprocs(workers())
    end
end
