using Test
using Ray
using Aqua
using Distributed

using ray_core_worker_julia_jll

include("setup.jl")
include("utils.jl")

# ENV["JULIA_DEBUG"] = "Ray"

@testset "Ray.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(Ray; ambiguities=false)
    end

    setup_ray_head_node() do
        include("function_manager.jl")
    end
end
