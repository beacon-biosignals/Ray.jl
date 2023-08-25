# copied from ray_core_worker_julia_jll tests
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
    Ray.init()
    try
        body()
    finally
        rayjll.shutdown_driver()
    end
end

macro process_eval(ex)
    expr = QuoteNode(ex)
    return esc(:(process_eval($expr)))
end

function process_eval(expr::Expr; stdout=devnull)
    # Avoid returning the result with STDOUT as other output and `atexit` hooks make it
    # difficult to read the serialized result.
    code = """
        using Serialization
        expr = deserialize(stdin)
        result_file = deserialize(stdin)
        result = eval(expr)
        open(result_file, "w") do io
            serialize(io, result)
        end
        """
    cmd = `$(Base.julia_cmd()) --project=$(Ray.project_dir()) -e $code`

    input = Pipe()
    err = Pipe()
    result_file = tempname()
    p = run(pipeline(cmd; stdin=input, stdout=stdout, stderr=err); wait=false)

    serialize(input, expr)
    serialize(input, result_file)
    wait(p)
    if success(p)
        return deserialize(result_file)
    else
        err_str = String(readavailable(err))
        error("Executing `process_eval` failed:\n\"\"\"\"\n$err_str\"\"\"\"")
    end
end
