using CxxWrap
using Mustache
using TOML

build_dir = @__DIR__()
pkg_uuid = TOML.parsefile(joinpath(build_dir, "..", "Project.toml"))["uuid"]
artifact_dir = joinpath(build_dir, "bazel-bin")
library_name = "julia_core_worker_lib.so"

dict = Dict(
    "JULIA_INCLUDE_DIR" => joinpath(Sys.BINDIR, "..", "include"),
    "CXXWRAP_PREFIX_DIR" => CxxWrap.prefix_path(),
)

template = Mustache.load(joinpath(build_dir, "WORKSPACE.bazel.tpl"))

open(joinpath(build_dir, "WORKSPACE.bazel"), "w+") do io
    Mustache.render(io, template, dict)
end

cd(build_dir) do
    run(`bazel build $library_name`)
end

if !isfile(joinpath(artifact_dir, library_name))
    error("Failed to build library: $(joinpath(artifact_dir, library_name))")
end

# Add entry to Overrides.toml
overrides_toml = joinpath(homedir(), ".julia", "artifacts", "Overrides.toml")
overrides_dict = TOML.parsefile(overrides_toml)
overrides_dict[pkg_uuid] = Dict("ray_core_worker_julia" => abspath(artifact_dir))
open(overrides_toml, "w") do io
    TOML.print(io, overrides_dict)
end
