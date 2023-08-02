using Base: SHA1
using CxxWrap
using Mustache
using Pkg.Artifacts: bind_artifact!
using Tar
using TOML
using UUIDs

const PKG_ID = UUID("c348cde4-7f22-4730-83d8-6959fb7a17ba")

function tree_hash_sha1(dir::AbstractString)
    buffer = IOBuffer()
    Tar.create(dir, buffer)
    return SHA1(Tar.tree_hash(seekstart(buffer)))
end

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

lib_path = joinpath(@__DIR__, "bazel-bin", "julia_core_worker_lib.so")

# Copy library to a clean directory so the tree SHA1
override_dir = joinpath(@__DIR__, "override")
override_lib_path = joinpath(override_dir, basename(lib_path))
isdir(override_dir) || mkdir(override_dir)
cp(lib_path, override_lib_path; force=true)

# Update artifact git-tree-sha1
artifacts_toml = joinpath(@__DIR__, "..", "Artifacts.toml")
bind_artifact!(
    artifacts_toml,
    "ray_core_worker_julia",
    Base.SHA1("0"^40);
    force=true,
)

# Add entry to Overrides.toml
overrides_toml = joinpath(homedir(), ".julia", "artifacts", "Overrides.toml")
overrides_dict = TOML.parsefile(overrides_toml)
overrides_dict[string(PKG_ID)] = Dict("ray_core_worker_julia" => abspath(override_dir))
open(overrides_toml, "w") do io
    TOML.print(io, overrides_dict)
end
