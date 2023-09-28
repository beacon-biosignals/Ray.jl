using CxxWrap
using Mustache
using TOML

build_dir = @__DIR__()
project_toml = joinpath(build_dir, "..", "Project.toml")
artifact_dir = joinpath(build_dir, "bazel-bin")
ray_dir = joinpath(build_dir, "ray")
ray_commit = readchomp(joinpath(build_dir, "ray_commit"))
library_name = "julia_core_worker_lib.so"

dict = Dict("JULIA_INCLUDE_DIR" => joinpath(Sys.BINDIR, "..", "include"),
            "CXXWRAP_PREFIX_DIR" => CxxWrap.prefix_path(),
            "RAY_DIR" => ray_dir)

template = Mustache.load(joinpath(build_dir, "WORKSPACE.bazel.tpl"))

open(joinpath(build_dir, "WORKSPACE.bazel"), "w+") do io
    Mustache.render(io, template, dict)
    return nothing
end

#! format: off
# Clone "ray" repo when the directory is missing or empty
isdir(ray_dir) && !isempty(readdir(ray_dir)) || cd(dirname(ray_dir)) do
    run(`git clone https://github.com/beacon-biosignals/ray $(basename(ray_dir))`)
    return nothing
end
#! format: on

# Ensure that library is always built against the same version of ray
if !("--no-checkout" in ARGS)
    run(`git -C $ray_dir fetch origin`)
    run(`git -C $ray_dir checkout $ray_commit`)
end

cd(build_dir) do
    run(`bazel build $library_name`)
    return nothing
end

if !isfile(joinpath(artifact_dir, library_name))
    error("Failed to build library: $(joinpath(artifact_dir, library_name))")
end

# Add entry to depot Overrides.toml
if !("--no-override" in ARGS)
    pkg_uuid = TOML.parsefile(project_toml)["uuid"]

    overrides_toml = joinpath(first(DEPOT_PATH), "artifacts", "Overrides.toml")
    overrides_dict = isfile(overrides_toml) ? TOML.parsefile(overrides_toml) :
                     Dict{String,Any}()
    overrides_dict[pkg_uuid] = Dict("ray_julia" => abspath(artifact_dir))
    open(overrides_toml, "w") do io
        TOML.print(io, overrides_dict)
        return nothing
    end
end
