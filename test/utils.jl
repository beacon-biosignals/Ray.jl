using ray_core_worker_julia_jll: initialize_coreworker_driver, shutdown_coreworker

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

function setup_core_worker(body)
    initialize_coreworker_driver("/tmp/ray/session_latest/sockets/raylet",
                                 "/tmp/ray/session_latest/sockets/plasma_store",
                                 "127.0.0.1:6379",
                                 "127.0.0.1",
                                 node_manager_port())
    try
        body()
    finally
        shutdown_coreworker()
    end
end
