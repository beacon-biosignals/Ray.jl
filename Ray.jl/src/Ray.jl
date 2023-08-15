"""
    Ray

This package provides user-facing interface for Julia-on-Ray.
"""
module Ray

using Base64
using Serialization
using ray_core_worker_julia_jll

include("function_manager.jl")

end
