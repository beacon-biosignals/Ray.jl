using Test
using Ray
using Aqua
using Distributed

using ray_core_worker_julia_jll

include("utils.jl")

# setup some modules for teh function manager tests...
module MyMod
f(x) = x + 1

module MySubMod
f(x) = x - 1
end # module MM

end # module M

module NotMyMod
using ..MyMod: f
g(x) = x - 1
end

ENV["JULIA_DEBUG"] = "Ray"

@testset "Ray.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(Ray; ambiguities=false)
    end

    setup_ray_head_node() do
        include("function_manager.jl")
    end
end
