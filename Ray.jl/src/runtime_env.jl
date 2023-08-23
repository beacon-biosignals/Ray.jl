struct RuntimeEnv
    project::String
end

RuntimeEnv(; project=dirname(Pkg.project().path)) = RuntimeEnv(project)

function json_dict(runtime_env::RuntimeEnv)
    # The keys of `context` must match what is supported by the Python `RuntimeEnvContext`:
    # https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_private/runtime_env/context.py#L20-L45
    context = Dict("env_vars" => Dict("JULIA_PROJECT" => runtime_env.project))

    return context
end
