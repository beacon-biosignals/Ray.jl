module ray_julia_jll

using Artifacts: @artifact_str
using CxxWrap
using CxxWrap.StdLib: StdVector, SharedPtr
using Serialization
using libcxxwrap_julia_jll

@wrapmodule(joinpath(artifact"ray_julia", "julia_core_worker_lib.so"))

function __init__()
    @initcxx
end  # __init__()

include("expr.jl")
include("common.jl")

end  # module ray_julia_jll
