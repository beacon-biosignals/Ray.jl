using Base: SHA1
using CxxWrap
using Mustache
using TOML
using UUIDs

const PKG_ID = UUID("c348cde4-7f22-4730-83d8-6959fb7a17ba")


dict = Dict(
    "JULIA_INCLUDE_DIR" => joinpath(Sys.BINDIR, "..", "include"),
    "CXXWRAP_PREFIX_DIR" => CxxWrap.prefix_path(),
)

template = Mustache.load(joinpath(@__DIR__, "WORKSPACE.bazel.tpl"))

open(joinpath(@__DIR__, "WORKSPACE.bazel"), "w+") do io
    Mustache.render(io, template, dict)
end

cd(@__DIR__) do
    run(`bazel build julia_core_worker_lib.so`)
end

artifact_dir = joinpath(@__DIR__, "bazel-bin")

# Add entry to Overrides.toml
overrides_toml = joinpath(homedir(), ".julia", "artifacts", "Overrides.toml")
overrides_dict = TOML.parsefile(overrides_toml)
overrides_dict[string(PKG_ID)] = Dict("ray_core_worker_julia" => abspath(artifact_dir))
open(overrides_toml, "w") do io
    TOML.print(io, overrides_dict)
end
