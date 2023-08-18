@testset "Submit task" begin
    # oid = submit_task(Int32 ∘ length, ["hello"])
    # result = String(take!(ray_core_worker_julia_jll.get(oid)))
    # @test all(isdigit, result)
    # @test parse(Int, result) == 5

    addme(x...) = Int32(sum(x))
    oid = submit_task(addme, [1, 2, 3])
    result = String(take!(ray_core_worker_julia_jll.get(oid)))
    @test all(isdigit, result)
    @test parse(Int, result) == 6
end
