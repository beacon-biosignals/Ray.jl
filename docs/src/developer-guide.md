# Developer Guide

For those wanting to contribute to Ray.jl this guide will assist you in creating a development environment allowing you update the Julia code and Ray C++ wrapper.

## Setting up your development environment

Building the Ray.jl project requires the following tools to be installed. This list is provided for informational purposes and typically users should follow the platform specific install sections.

- [Julia](https://julialang.org/downloads/) version ≥ `v1.8`
- Python version ≥ `v3.7`
    - [Python venv](https://docs.python.org/3/library/venv.html)
- [Bazelisk](https://github.com/bazelbuild/bazelisk)
- GCC / G++ ≥ `v9`

### Install Dependencies on macOS

1. Install [Homebrew](https://brew.sh/)
2. Install [Julia](https://julialang.org/downloads/)
3. Install Python (we recommend via [`pyenv`](https://github.com/pyenv/pyenv#homebrew-in-macos))
4. Navigate to the root of the Ray.jl repo
5. Install [Ray dependencies](https://docs.ray.io/en/latest/ray-contribute/development.html#preparing-to-build-ray-on-macos):

```sh
brew update
brew install bazelisk wget
```

### Install dependencies on Linux

1. Install [Julia](https://julialang.org/downloads/)
2. Install Python
3. Navigate to the root of the Ray.jl repo
4. Install [Ray dependencies](https://docs.ray.io/en/latest/ray-contribute/development.html#preparing-to-build-ray-on-linux):

```sh
# Add a PPA containing gcc-9 for older versions of Ubuntu.
sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
sudo apt-get update
sudo apt-get install -y build-essential curl git gcc-9 g++-9 pkg-config psmisc unzip
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 \
  --slave /usr/bin/g++ g++ /usr/bin/g++-9 \
  --slave /usr/bin/gcov gcov /usr/bin/gcov-9

# Install Bazelisk
case $(uname -m) in
  x86_64) ARCH=amd64;;
  aarch64) ARCH=arm64;;
esac

curl -fsSLo bazel https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-${ARCH}
sudo install bazel /usr/local/bin
```

### Prepare Python virtual environment

We recommend always using the same virtual environment as otherwise Bazel will perform unnecessary rebuilds when using switching between different versions of Python.

```sh
python -m venv venv
source venv/bin/activate
# make sure we're using up-to-date version of pip and wheel:
python -m pip install --upgrade pip wheel
```

### Build Ray.jl

The initial Ray.jl build can be done as follows:

```sh
source venv/bin/activate
julia --project=build -e 'using Pkg; Pkg.instantiate()'

# Build "ray_julia" library. Will adds an entry in "~/.julia/artifacts/Overrides.toml" unless `--no-override` is specified
julia --project=build build/build_library.jl
```

Subsequent builds can done via:

```sh
source venv/bin/activate
julia --project=build build/build_library.jl && julia --project -e 'using Ray' && julia --project
```

If you decide to switch back to using the the pre-built binaries you will have to revert the modification to your `~/.julia/artifacts/Overrides.toml`.

### Build Ray CLI/Backend

We currently rely on a patched version of upstream Ray CLI that is aware of Julia as a supported language and knows how to launch Julia worker processes. Until these changes are [upstreamed to the Ray project](https://github.com/ray-project/ray/issues/39637) we'll need to keep using a patched version of the Ray CLI:

```sh
source venv/bin/activate
cd build/ray/python
pip install --verbose .
cd -
```

### Test the build

Once you have [built Ray.jl](#build-rayjl) and the [Ray CLI](#build-ray-clibackend) you can validate your build by running the test suite:

```sh
source venv/bin/activate
julia --project -e 'using Pkg; Pkg.test()'
```
