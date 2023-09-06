using CxxWrap
using Test
using ray_core_worker_julia_jll: JuliaFunctionDescriptor, function_descriptor

include("utils.jl")

module M
f(x) = x + 1
end

@testset "ray_core_worker_julia_jll.jl" begin
    include("buffer.jl")
    include("function_descriptor.jl")

    setup_ray_head_node() do
        # GCS client only needs head node
        include("gcs_client.jl")
        setup_core_worker() do
            include("put_get.jl")
        end
    end
end
