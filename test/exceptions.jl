@testset "RayTaskException" begin
    @testset "showerror" begin
        e = ErrorException("foo")
        e = Ray.RayTaskException("test2", 2, ip"127.0.0.1", "t2",
                                 CapturedException(e, backtrace()))
        rte = Ray.RayTaskException("test1", 1, ip"127.0.0.1", "t1",
                                   CapturedException(e, backtrace()))

        str = sprint(showerror, rte)
        #! format: off
        @test occursin(r"^\QRayTaskException: test1 (pid=1, ip=127.0.0.1, task_id=t1)\E"m, str)
        @test occursin(r"^\Qnested exception: RayTaskException: test2 (pid=2, ip=127.0.0.1, task_id=t2)\E"m, str)
        @test occursin(r"^\Qnested exception: foo\E"m, str)
        #! format: on

        structure_regex = r"""
            ^RayTaskException: test1[^\n]++

            nested exception: RayTaskException: test2[^\n]++
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
        @test occursin(r"^\QRayTaskException: test1 (pid=1, ip=127.0.0.1, task_id=t1)\E"m, str)
        @test occursin(r"^\Qnested exception: RayTaskException: test2 (pid=2, ip=127.0.0.1, task_id=t2)\E"m, str)
        @test occursin(r"^\Qnested exception: foo\E"m, str)
        #! format: on

        structure_regex = r"""
            ^RayTaskException: test1[^\n]++
            nested exception: RayTaskException: test2[^\n]++
            nested exception: foo$"""s
        @test occursin(structure_regex, str)
    end
end
