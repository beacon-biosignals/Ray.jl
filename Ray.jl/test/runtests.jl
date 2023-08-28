using Aqua
using Ray
using Test

import ray_core_worker_julia_jll as rayjll

include("setup.jl")
include("utils.jl")

# ENV["JULIA_DEBUG"] = "Ray"

@testset "Ray.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(Ray; ambiguities=false)
    end

    include("runtime_env.jl")

    setup_ray_head_node() do
        include("function_manager.jl")
        setup_core_worker() do
            include("object_store.jl")
            include("task.jl")
        end
    end
end
