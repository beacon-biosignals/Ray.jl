# copied from ray_julia_jll tests
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
        ray_jll.shutdown_driver()
    end
end

# Useful in running tests which require us to re-run `Ray.init` which currently can only be
# called once as it is infeasible to reset global `Ref`'s using `isassigned` conditionals.
macro process_eval(ex)
    expr = QuoteNode(ex)
    return esc(:(process_eval($expr)))
end

function process_eval(expr::Expr; stdout=devnull)
    # Avoid returning the result with STDOUT as other output and `atexit` hooks make it
    # difficult to read the serialized result.
    code = quote
        using Serialization

        # Evaluate each line individually (like `include_string`) to allow usage of loaded
        # code. Additionally, this provides useful stacktraces from user code.
        function eval_toplevel(ast::Expr)
            line_and_ex = Expr(:toplevel, LineNumberNode(1, :unknown), nothing)
            result = nothing
            for ex in ast.args
                if ex isa LineNumberNode
                    line_and_ex.args[1] = ex
                else
                    line_and_ex.args[2] = ex
                    result = eval(line_and_ex)
                end
            end
            return result
        end

        ast = deserialize(stdin)
        result_file = deserialize(stdin)

        open(result_file, "w") do io
            serialize(io, eval_toplevel(ast))
        end
    end

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
