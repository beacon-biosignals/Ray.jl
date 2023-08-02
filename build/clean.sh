#!/bin/bash

# Delete all files created by the build script

pushd build
rm -rf /tmp/julia
rm WORKSPACE.bazel
rm bazel-*
popd
