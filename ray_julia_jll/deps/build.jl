using CxxWrap
using Mustache
using TOML

build_dir = @__DIR__()
pkg_uuid = TOML.parsefile(joinpath(build_dir, "..", "Project.toml"))["uuid"]
artifact_dir = joinpath(build_dir, "bazel-bin")
ray_dir = joinpath(build_dir, "ray")
library_name = "julia_core_worker_lib.so"

dict = Dict(
    "JULIA_INCLUDE_DIR" => joinpath(Sys.BINDIR, "..", "include"),
    "CXXWRAP_PREFIX_DIR" => CxxWrap.prefix_path(),
    "RAY_DIR" => ray_dir,
)

template = Mustache.load(joinpath(build_dir, "WORKSPACE.bazel.tpl"))

open(joinpath(build_dir, "WORKSPACE.bazel"), "w+") do io
    Mustache.render(io, template, dict)
end

isdir(ray_dir) || cd(dirname(ray_dir)) do
    run(`git clone https://github.com/beacon-biosignals/ray $(basename(ray_dir))`)
end

cd(build_dir) do
    run(`bazel build $library_name`)
end

if !isfile(joinpath(artifact_dir, library_name))
    error("Failed to build library: $(joinpath(artifact_dir, library_name))")
end
