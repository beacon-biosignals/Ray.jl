@testset "Submit task" begin
    oid1 = submit_task(length, "hello")
    oid2 = submit_task(max, 1, 2)

    result1 = deserialize(IOBuffer(take!(ray_core_worker_julia_jll.get(oid1))))
    @test result1 isa Int
    @test result1 == 5

    result2 = deserialize(IOBuffer(take!(ray_core_worker_julia_jll.get(oid2))))
    @test result2 isa Int
    @test result2 == 2
end
