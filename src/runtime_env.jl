struct RuntimeEnv
    project::String
    package_imports::Expr

    function RuntimeEnv(project, package_imports)
        return new(project, process_import_statements(package_imports))
    end
end

function RuntimeEnv(; project=project_dir(), package_imports=Expr(:block))
    return RuntimeEnv(project, package_imports)
end

function json_dict(runtime_env::RuntimeEnv)
    # TODO: Support user-defined environmental variables in the future
    # https://github.com/beacon-biosignals/Ray.jl/issues/56
    env_vars = Dict("JULIA_PROJECT" => runtime_env.project)

    # Avoid including package imports if the expression is an empty block
    imports = runtime_env.package_imports
    if imports.head !== :block || !isempty(imports.args)
        env_vars["JULIA_RAY_PACKAGE_IMPORTS"] = base64encode(serialize, imports)
    end

    code = "using $(@__MODULE__); start_worker()"
    cmd = `$(Base.julia_cmd()) -e $code`

    # The keys of `context` must match what is supported by the Python `RuntimeEnvContext`:
    # https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_private/runtime_env/context.py#L20-L45
    context = Dict("command" => cmd.exec, "env_vars" => env_vars)

    return context
end

function _serialize(runtime_env::RuntimeEnv)
    return JSON3.write(json_dict(runtime_env))
end

# https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/protobuf/runtime_env_common.proto#L39-L46
struct RuntimeEnvInfo
    runtime_env::RuntimeEnv
end

function json_dict(runtime_env_info::RuntimeEnvInfo)
    serialized_runtime_env = _serialize(runtime_env_info.runtime_env)
    return Dict("serialized_runtime_env" => serialized_runtime_env)
end

function _serialize(runtime_env_info::RuntimeEnvInfo)
    return JSON3.write(json_dict(runtime_env_info))
end

# https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/protobuf/common.proto#L324-L349
struct JobConfig
    runtime_env_info::RuntimeEnvInfo
end

function json_dict(job_config::JobConfig)
    return Dict("runtime_env_info" => json_dict(job_config.runtime_env_info))
end

# TODO: We may want to use separate functions for protobuf serialization and JSON
# serialization. Mostly this matters if Ray serializes the same message with both formats.
# https://github.com/beacon-biosignals/Ray.jl/issues/57
function _serialize(job_config::JobConfig)
    job_config_json = JSON3.write(json_dict(job_config))
    return ray_jll.serialize_job_config_json(job_config_json)
end

function process_import_statements(ex::Expr)
    if ex.head === :using || ex.head === :import
        return ex
    elseif ex.head === :block
        imports = Expr(:block)
        for arg in ex.args
            # Avoid using `remove_linenums!` here as this function is non-mutating and
            # removing line number information from the original expression may make it more
            # difficult for the user to read stacktrace information due to runtime issues.
            arg isa LineNumberNode && continue
            push!(imports.args, process_import_statements(arg))
        end
        return imports
    else
        msg = "Expected `using` or `import` statements, instead found: $(repr(ex))"
        throw(ArgumentError(msg))
    end
end

project_dir() = dirname(Pkg.project().path)
