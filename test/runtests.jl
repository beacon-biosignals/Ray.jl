using Aqua
using CxxWrap: CxxPtr, StdVector
using CxxWrap.StdLib: UniquePtr
using Ray
using Serialization
using Test

import ray_julia_jll as ray_jll

include("setup.jl")
include("utils.jl")

# ENV["JULIA_DEBUG"] = "Ray"

@testset "Ray.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(Ray; ambiguities=false)
    end

    include("object_ref.jl")
    include("runtime_env.jl")
    include("remote_function.jl")

    setup_ray_head_node() do
        include("function_manager.jl")
        setup_core_worker() do
            include("runtime.jl")
            include("object_store.jl")
            include("task.jl")
        end
    end
end
