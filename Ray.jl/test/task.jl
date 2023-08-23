@testset "Submit task" begin
    oid1 = submit_task(Int32 ∘ length, "hello")
    addme(x...) = Int32(sum(x))
    oid2 = submit_task(addme, 1, 2, 3)

    result1 = String(take!(ray_core_worker_julia_jll.get(oid1)))
    @test all(isdigit, result1)
    @test parse(Int, result1) == 5

    result2 = String(take!(ray_core_worker_julia_jll.get(oid2)))
    @test all(isdigit, result2)
    @test parse(Int, result2) == 6

    # task with no args
    oid3 = submit_task(getpid)
    result3 = String(take!(ray_core_worker_julia_jll.get(oid3)))
    @test all(isdigit, result2)
    @test parse(Int32, result2) != getpid()
end
