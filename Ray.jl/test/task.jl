@testset "Submit task" begin
    oid1 = submit_task(length, "hello")
    oid2 = submit_task(max, 0x00, 0xff)

    result1 = deserialize(IOBuffer(take!(ray_core_worker_julia_jll.get(oid1))))
    @test result1 isa Int
    @test result1 == 5

    result2 = deserialize(IOBuffer(take!(ray_core_worker_julia_jll.get(oid2))))
    @test result2 isa UInt8
    @test result2 == 0xff
end
