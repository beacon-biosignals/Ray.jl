"""
    Ray

This package provides user-facing interface for Julia-on-Ray.
"""
module Ray

using ArgParse
using Base64
using Dates
using JSON3
using Logging
using LoggingExtras
using Pkg
using Serialization

import ray_core_worker_julia_jll as rayjll

export start_worker, submit_task

include("function_manager.jl")
include("runtime_env.jl")
include("runtime.jl")
include("object_store.jl")

end
