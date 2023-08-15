"""
    Ray

This package provides user-facing interface for Julia-on-Ray.
"""
module Ray

using ArgParse
using Base64
using Logging
using LoggingExtras
using Serialization
using ray_core_worker_julia_jll

include("runtime.jl")
include("function_manager.jl")

end
