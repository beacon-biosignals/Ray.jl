export ray_core_worker_julia

using libcxxwrap_julia_jll
JLLWrappers.@generate_wrapper_header("ray_core_worker_julia")
JLLWrappers.@declare_library_product(ray_core_worker_julia, "julia_core_worker_lib.so")
function __init__()
    JLLWrappers.@generate_init_header(libcxxwrap_julia_jll)
    JLLWrappers.@init_library_product(
        ray_core_worker_julia,
        "julia_core_worker_lib.so",
        RTLD_GLOBAL,
    )

    JLLWrappers.@generate_init_footer()
end  # __init__()
