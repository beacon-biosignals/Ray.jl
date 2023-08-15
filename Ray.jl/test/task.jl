@testset "Submit task" begin
    oid = submit_task(getpid)
    pid = String(take!(ray_core_worker_julia_jll.get(oid)))
    @test all(isdigit, pid)
    @test parse(Int, pid) != getpid()
end
