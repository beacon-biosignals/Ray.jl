using Aqua
using Base64: Base64DecodePipe
using CxxWrap: CxxPtr, StdVector
using CxxWrap.StdLib: UniquePtr
using JSON3: JSON3
using Ray
using Serialization
using Sockets: @ip_str
using Test

using Ray: ray_julia_jll, ray_julia_jll as ray_jll

include("setup.jl")
include("utils.jl")

# ENV["JULIA_DEBUG"] = "Ray"

@testset "Ray.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(Ray; ambiguities=false)
    end


    include("exceptions.jl")
    include("runtime_env.jl")
    include("remote_function.jl")

    setup_ray_head_node() do
        include("function_manager.jl")
        setup_core_worker() do
            include("object_ref.jl")
            include("ray_serializer.jl")
            include("runtime.jl")
            include("object_store.jl")
            include("task.jl")

            # TODO: Testing ray_julia_jll after Ray is wrong
            include("ray_julia_jll/runtests.jl")
        end
    end
end
