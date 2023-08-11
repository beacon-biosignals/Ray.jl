using Test
using Ray
using Aqua

using ray_core_worker_julia_jll

include("utils.jl")

@testset "Ray.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(Ray; ambiguities=false)
    end

    setup_ray_head_node() do
        @tesset "function manager" begin include("function_manager.jl") end
    end
end
