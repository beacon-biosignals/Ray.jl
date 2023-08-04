function setup_ray_head_node(body)
    prestarted = success(`ray status`)
    if !prestarted
        @info "Starting local head node"
        run(pipeline(`ray start --head`, stdout=devnull))
    end

    try
        body()
    finally
        !prestarted && run(pipeline(`ray stop`, stdout=devnull))
    end
end

function setup_core_worker(body)
    initialize_coreworker()
    try
        body()
    finally
        shutdown_coreworker()
    end
end
