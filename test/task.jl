@testset "Submit task" begin
    oid = submit_task()
    pid = String(take!(get(oid)))
    @test all(isdigit, pid)
    @test parse(Int, pid) != getpid()
end
