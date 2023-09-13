"""
    Ray

This package provides user-facing interface for Julia-on-Ray.
"""
module Ray

using ArgParse
using Base64
using CxxWrap: CxxPtr, CxxRef, StdVector, isnull
using CxxWrap.StdLib: SharedPtr
using JSON3
using Logging
using LoggingExtras
using Pkg
using Serialization: Serialization, AbstractSerializer, Serializer, deserialize,
    reset_state, serialize, serialize_type, writeheader

import ray_julia_jll as ray_jll

export start_worker, submit_task, @ray_import, ObjectRef

include("function_manager.jl")
include("runtime_env.jl")
include("remote_function.jl")
include("runtime.jl")
include("object_ref.jl")
include("ray_serializer.jl")
include("object_store.jl")

end
