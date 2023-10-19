module ray_julia_jll

using Artifacts: @artifact_str
using CxxWrap
using CxxWrap.StdLib: StdVector, SharedPtr
using Serialization: Serialization, AbstractSerializer, deserialize, serialize,
                     serialize_type
using libcxxwrap_julia_jll

abstract type BaseID end

@wrapmodule(joinpath(artifact"ray_julia", "julia_core_worker_lib.so"))

function __init__()
    @initcxx
end  # __init__()

include("upstream_fixes.jl")
include("expr.jl")
include("common.jl")

end  # module ray_julia_jll
