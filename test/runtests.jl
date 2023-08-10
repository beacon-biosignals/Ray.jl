using CxxWrap
using Test
using ray_core_worker_julia_jll: initialize_coreworker, shutdown_coreworker, put, get,
      function_descriptor, FunctionDescriptor

include("utils.jl")

@testset "ray_core_worker_julia_jll.jl" begin
    include("buffer.jl")

    setup_ray_head_node() do
        # GCS client only needs head node
        include("gcs_client.jl")
        setup_core_worker() do
            include("put_get.jl")
            include("function_descriptor.jl")
        end
    end
end
