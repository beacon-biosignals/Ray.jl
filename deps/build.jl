using CxxWrap
using Mustache
using TOML

pkg_uuid = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))["uuid"]
artifact_dir = joinpath(@__DIR__, "bazel-bin")
library_name = "julia_core_worker_lib.so"

dict = Dict(
    "JULIA_INCLUDE_DIR" => joinpath(Sys.BINDIR, "..", "include"),
    "CXXWRAP_PREFIX_DIR" => CxxWrap.prefix_path(),
)

template = Mustache.load(joinpath(@__DIR__, "WORKSPACE.bazel.tpl"))

open(joinpath(@__DIR__, "WORKSPACE.bazel"), "w+") do io
    Mustache.render(io, template, dict)
end

cd(@__DIR__) do
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
