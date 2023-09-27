# Installation

Ultimately we aim to make installing Ray.jl as simple as running `Pkg.add("Ray")`. However, at the moment there are some manual steps are required to install Ray.jl. For users with machines using the Linux x86_64 or macOS aarch64 (Apple Silicon) platforms we have provided pre-built binaries for each Ray.jl release.

To install these dependencies and Ray.jl run the following:

```sh
# Install the Ray CLI
PYTHON=$(python3 --version | perl -ne '/(\d+)\.(\d+)/; print "cp$1$2-cp$1$2"')
case $(uname -s) in
    Linux) OS=manylinux2014;;
    Darwin) OS=macosx_13_0;;
esac
ARCH=$(uname -m)
RELEASE="ray-2.5.1+1"
pip install -U "ray[default] @ https://github.com/beacon-biosignals/ray/releases/download/$RELEASE/${RELEASE%+*}-${PYTHON}-${OS}_${ARCH}.whl" "pydantic<2"

# Install the Julia packages "ray_julia_jll" and "Ray"
TAG="v0.1.0" julia -e 'using Pkg; Pkg.add([PackageSpec(url="https://github.com/beacon-biosignals/Ray.jl", subdir="ray_julia_jll", rev=ENV["TAG"]), PackageSpec(url="https://github.com/beacon-biosignals/Ray.jl", rev=ENV["TAG"])])'
```

Users attempting to use Ray.jl on other platforms can attempt to [build the package from source](./developer-guide.md).
