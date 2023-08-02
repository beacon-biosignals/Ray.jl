#!/bin/bash

# Hacky build script for building the julia_core_worker_lib.so and linking it to Artifacts.toml.

pushd build

JULIA_EXEC_PATH=$(which julia | xargs realpath)             # path/to/julia-1.9.1/bin/julia
JULIA_ROOT_PATH=$(dirname $JULIA_EXEC_PATH | xargs dirname) # path/to/julia-1.9.1
JULIA_INCLUDE_PATH="$JULIA_ROOT_PATH/include"               # path/to/julia-1.9.1/include

mkdir -p /tmp/julia
ln -s $JULIA_INCLUDE_PATH /tmp/julia/include
ln -s $JULIA_EXEC_PATH /tmp/julia/bin

# /home/ubuntu/.julia/artifacts/88a033de19250acca6784647964d43d7121a06aa
CXXWRAP_PREFIX_PATH=$(julia --project=. -e 'using CxxWrap; println(CxxWrap.prefix_path())')
sed -e 's|CXXWRAP_PREFIX_PATH|'$CXXWRAP_PREFIX_PATH'|g' WORKSPACE.bazel.tmp > WORKSPACE.bazel

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
cat >> ~/.julia/artifacts/Overrides.toml <<EOF
$GIT_TREE_SHA = "$(pwd)/overrides"
EOF

julia --project -e 'using Pkg; Pkg.instantiate()'
