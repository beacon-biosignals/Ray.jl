using CxxWrap
using Test
using ray_core_worker_julia_jll: FunctionDescriptor, function_descriptor
using ray_core_worker_julia_jll: initialize_coreworker, shutdown_coreworker
using ray_core_worker_julia_jll: get, put, submit_task

include("utils.jl")

@testset "ray_core_worker_julia_jll.jl" begin
    include("buffer.jl")

    setup_ray_head_node() do
        # GCS client only needs head node
        include("gcs_client.jl")
        setup_core_worker() do
            include("put_get.jl")
            include("function_descriptor.jl")
            include("task.jl")
        end
    end
end
