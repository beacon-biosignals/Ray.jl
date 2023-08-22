struct RuntimeEnv
    project::String
    package_imports::Expr
end

function RuntimeEnv(; project=project_dir(), package_imports=Expr(:block))
    # TODO: Possibly restrict `imports` to `using` or `import` expressions
    return RuntimeEnv(project, package_imports)
end

function json_dict(runtime_env::RuntimeEnv)
    env_vars = Dict("JULIA_PROJECT" => runtime_env.project)

    # TODO: Error when package imports is something strange
    ex = runtime_env.package_imports
    if ex.head == :block && !isempty(ex.args) || ex.head in (:using, :import)
        env_vars["JULIA_RAY_PACKAGE_IMPORTS"] = base64encode(serialize, ex)
    end

    # The keys of `context` must match what is supported by the Python `RuntimeEnvContext`:
    # https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_private/runtime_env/context.py#L20-L45
    context = Dict("env_vars" => env_vars)

    return context
end

project_dir() = dirname(Pkg.project().path)
