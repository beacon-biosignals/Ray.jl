using Base64: base64encode
using CxxWrap
using JSON3: JSON3
using Test
using Ray: ray_julia_jll

include("utils.jl")

module M
f(x) = x + 1
end

@testset "ray_julia_jll.jl" begin
    include("buffer.jl")
    include("function_descriptor.jl")
    include("address.jl")
    include("objectid.jl")

    # setup_ray_head_node() do
        # GCS client only needs head node
        include("gcs_client.jl")
        # setup_core_worker() do
            include("put_get.jl")
            include("reference_counting.jl")
        # end
    # end
end
