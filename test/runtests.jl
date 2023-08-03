using ray_core_worker_julia_jll: initialize_coreworker, shutdown_coreworker, put, get
using Test

spawn_head = !success(`ray status`)
if spawn_head
    @info "Starting local head node"
    run(pipeline(`ray start --head`, stdout=devnull))
end

initialize_coreworker()

@testset "ray_core_worker_julia_jll.jl" begin
    try
        obj_ref1 = put("Greetings from Julia!")
        obj_ref2 = put("Take me to your leader")

        @test get(obj_ref2) == "Take me to your leader"
        @test get(obj_ref1) == "Greetings from Julia!"
    finally
        shutdown_coreworker()
        spawn_head && run(pipeline(`ray stop`, stdout=devnull))
    end
end
