# Installation

Ultimately we aim to make installing Ray.jl as simple as running `Pkg.add("Ray")`. However, at the moment there are some manual steps are required to install Ray.jl. For users with machines using the Linux x86_64 or macOS aarch64 (Apple Silicon) platforms we have provided pre-built binary dependencies for each Ray.jl release.

Additionally, the pre-built dependencies requires you are using the following versions of Julia and Python:

- Julia 1.8 - 1.9 (Linux x86_64 / macOS aarch64)
- Python 3.7 - 3.11

To install the pre-built version of Ray.jl run:

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

ray start --head && ray stop

# Install the Ray.jl Julia package
julia -e 'using Pkg; Pkg.add(PackageSpec(url="https://github.com/beacon-biosignals/Ray.jl", rev="v0.0.4"))'
```

Users attempting to use Ray.jl on other platforms can attempt to [build the package from source](./developer-guide.md).
