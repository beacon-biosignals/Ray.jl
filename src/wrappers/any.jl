# export ray_core_worker_julia

using CxxWrap
using libcxxwrap_julia_jll

JLLWrappers.@generate_wrapper_header("ray_core_worker_julia")
JLLWrappers.@declare_library_product(ray_core_worker_julia, "julia_core_worker_lib.so")
@wrapmodule(joinpath(artifact"ray_core_worker_julia", "julia_core_worker_lib.so"))

function __init__()
    JLLWrappers.@generate_init_header(libcxxwrap_julia_jll)
    JLLWrappers.@init_library_product(
        ray_core_worker_julia,
        "julia_core_worker_lib.so",
        RTLD_GLOBAL,
    )

    JLLWrappers.@generate_init_footer()
    @initcxx
end  # __init__()

function node_manager_port()
    line = open("/tmp/ray/session_latest/logs/raylet.out") do io
        while !eof(io)
            line = readline(io)
            if contains(line, "NodeManager server started")
                return line
            end
        end
    end

    m = match(r"port (\d+)", line)
    return m !== nothing ? parse(Int, m[1]) : error("Unable to find port")
end

initialize_coreworker() = initialize_coreworker(node_manager_port())
