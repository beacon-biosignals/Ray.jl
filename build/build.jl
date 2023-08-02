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

lib_path = joinpath(@__DIR__, "bazel-bin", "julia_core_worker_lib.so")

override_dir = joinpath(@__DIR__, "override")
mkdir(override_dir)
cp(lib_path, joinpath(override_dir, basename(lib_path)))

function git_tree_sha1(dir::AbstractString)
    buffer = IOBuffer()
    Tar.create(dir, buffer)
    Tar.tree_hash(seekstart(buffer))
end


overrides_path = joinpath(homedir(), ".julia", "artifacts", "Overrides.toml")
toml = TOML.parsefile(overrides_path)
toml[string(PKG_ID)] = Dict("ray_core_worker_julia" => abspath(lib_path))
open(overrides_path, "w") do io
    TOML.print(io, toml)
end



#=
artifact_dir = joinpath(@__DIR__, "overrides")

mkdir(artifact_dir)
cp(lib_path, joinpath(artifact_dir, basename(lib_path)))
x = Tar.create(artifact_dir, IOBuffer()) do



git_tree_sha1 =

cat > ~/.julia/artifacts/Overrides.toml <<EOF
$GIT_TREE_SHA = "$(pwd)/overrides"


cp build/bazel-out/k8-opt/bin/julia_core_worker_lib.so overrides/lib
=#


#=
#!/bin/bash

# Hacky build script for building the julia_core_worker_lib.so and linking it to Artifacts.toml.

pushd build

JULIA_EXEC_PATH="$(realpath "$(which julia)")"                 # path/to/julia-1.9.1/bin/julia
JULIA_INCLUDE_PATH="$(dirname "$JULIA_EXEC_PATH")/../include"  # path/to/julia-1.9.1/include



[ -f ~/.julia/artifacts/Overrides.toml ] && rm ~/.julia/artifacts/Overrides.toml

# /home/ubuntu/.julia/artifacts/88a033de19250acca6784647964d43d7121a06aa
CXXWRAP_PREFIX_PATH=$(julia --project=. -e 'using CxxWrap; println(CxxWrap.prefix_path())')
env \
    JULIA_INCLUDE_PATH="$JULIA_INCLUDE_PATH" \
    CXXWRAP_PREFIX_PATH="$CXXWRAP_PREFIX_PATH" \
    envsubst < WORKSPACE.bazel.tmp > WORKSPACE.bazel

bazel build julia_core_worker_lib.so
popd

rm -rf overrides/*
mkdir overrides/{include,lib,share}  # include and share are empty
cp build/bazel-out/k8-opt/bin/julia_core_worker_lib.so overrides/lib

# Get git-tree-sha1 without compressing the files. This isn't the same as Tar.tree_hash.
GIT_TREE_SHA=$(git ls-files -s overrides | git hash-object --stdin)

# overwrite Artifacts.toml
cat > Artifacts.toml <<EOF
[ray_core_worker_julia]
git-tree-sha1 = "$GIT_TREE_SHA"
EOF

# append to Overrides.toml
cat > ~/.julia/artifacts/Overrides.toml <<EOF
$GIT_TREE_SHA = "$(pwd)/overrides"
EOF




; @show include_dir, "julia.h" in readdir(include_dir)
=#
