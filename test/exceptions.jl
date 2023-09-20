@testset "RayTaskException" begin
    @testset "showerror" begin
        e = ErrorException("foo")
        e = Ray.RayTaskException("test2", 2, ip"127.0.0.1", CapturedException(e, backtrace()))
        rte = Ray.RayTaskException("test1", 1, ip"127.0.0.1", CapturedException(e, backtrace()))

        str = sprint(showerror, rte)
        @test occursin(r"\A\QRayTaskException: test1 (pid=1, ip=127.0.0.1)\E"m, str)
        @test occursin(r"^\Qnested exception: RayTaskException: test2 (pid=2, ip=127.0.0.1)\E"m, str)
        @test occursin(r"^\Qnested exception: foo\E"m, str)

        structure_regex = r"""
            ^RayTaskException:[^\n]++

            nested exception: RayTaskException[^\n]++
            Stacktrace:
              ([^\n]++\n?)+

            nested exception: foo
            Stacktrace:
              ([^\n]++\n?)+$"""s
        @test occursin(structure_regex, str)
    end
end
