# copied from ray_julia_jll tests
function setup_ray_head_node(body)
    prestarted = success(`ray status`)
    if !prestarted
        @info "Starting local head node"
        run(pipeline(`ray start --head`; stdout=devnull))
    end

    try
        body()
    finally
        !prestarted && run(pipeline(`ray stop`; stdout=devnull))
    end
end

function setup_core_worker(body)
    Ray.init()
    try
        body()
    finally
        # ObjectRef finalizers make core worker API call
        # (`RemoveLocalReference`) that needs to complete before tearing down
        # the core worker.  If we don't GC and insert a yield point here, we
        # race conditions where the finalizers run at the same time as the core
        # worker is being torn down, which leads to segfaults on ~50% of the
        # runs.
        GC.gc()
        yield()
        ray_jll.shutdown_driver()
    end
end

local_count(o::Ray.ObjectRef) = local_count(o.oid_hex)
local_count(oid_hex) = first(get(Ray.get_all_reference_counts(), oid_hex, 0))

# Useful in running tests which require us to re-run `Ray.init` which currently can only be
# called once as it is infeasible to reset global `Ref`'s using `isassigned` conditionals.
macro process_eval(ex...)
    kwargs = ex[1:(end - 1)]
    expr = QuoteNode(ex[end])
    return esc(:(process_eval($expr; $(kwargs...))))
end

function process_eval(expr::Expr; stdout=devnull, stderr=devnull)
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
            return nothing
        end
    end

    cmd = `$(Base.julia_cmd()) --project=$(Ray.project_dir()) -e $code`

    input = Pipe()
    stderr = stderr === devnull ? Pipe() : stderr
    result_file = tempname()
    p = run(pipeline(cmd; stdin=input, stdout, stderr); wait=false)

    serialize(input, expr)
    serialize(input, result_file)
    wait(p)
    if success(p)
        return deserialize(result_file)
    elseif stderr isa Pipe || stderr isa IOBuffer
        err_str = if stderr isa Pipe
            String(readavailable(stderr))
        else
            String(take!(stderr))
        end
        error("Executing `process_eval` failed:\n\"\"\"\"\n$err_str\"\"\"\"")
    else
        error("Executing `process_eval` failed")
    end
end
