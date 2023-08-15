"""
    Ray

This package provides user-facing interface for Julia-on-Ray.
"""
module Ray

using ArgParse
using Base64
using Logging
using LoggingExtras
using Pkg
using Serialization

using ray_core_worker_julia_jll: shutdown_coreworker

import ray_core_worker_julia_jll as rayjll

export start_worker, initialize_coreworker, shutdown_coreworker, submit_task
include("runtime.jl")

include("function_manager.jl")

end