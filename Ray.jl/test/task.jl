@testset "Submit task" begin
    oid = submit_task(length, ["hello"])
    result = String(take!(ray_core_worker_julia_jll.get(oid)))
    @test all(isdigit, result)
    @test parse(Int, result) == 5
end
