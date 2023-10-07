"""
    Ray

This package provides user-facing interface for Julia-on-Ray.
"""
module Ray

using ArgParse
using Base64
using CxxWrap: CxxPtr, CxxRef, StdString, StdVector, isnull
using CxxWrap.StdLib: SharedPtr
using JSON3
using Logging
using LoggingExtras
using Pkg
using Serialization: Serialization, AbstractSerializer, Serializer, deserialize,
                     reset_state, serialize, serialize_type, ser_version, writeheader
using Sockets: IPAddr, getipaddr

export start_worker, submit_task, @ray_import, ObjectRef

# exceptions
export RayError, RaySystemError, RayTaskError

include(joinpath("ray_julia_jll", "ray_julia_jll.jl"))
using .ray_julia_jll: ray_julia_jll, ray_julia_jll as ray_jll

include("exceptions.jl")
include("function_manager.jl")
include("runtime_env.jl")
include("remote_function.jl")
include("runtime.jl")
include("object_ref.jl")
include("ray_serializer.jl")
include("object_store.jl")

end
