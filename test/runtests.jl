using ray_core_worker_julia_jll: initialize_coreworker, shutdown_coreworker, put, get,
      function_descriptor, FunctionDescriptor
using Test

include("utils.jl")

@testset "ray_core_worker_julia_jll.jl" begin
    setup_ray_head_node() do
        setup_core_worker() do
            include("put_get.jl")
            include("function_descriptor.jl")
        end
    end
end
