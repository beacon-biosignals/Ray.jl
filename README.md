# Ray.jl

The `ray_julia_jll` is the Julia C++ wrapper that interfaces with the Ray.io project's shared core worker library.

At the moment the package requires that the shared libraries are built directly on the host system and does not provide any precreated cross-compiled libraries. We hope to turn this package into a full fledged JLL but this direct build process will work as we experiment with interfacing with the Ray core worker C++ interface.

## Setup (manual/dev build)

Ultimately our aim is to make installing Ray.jl as simple as `Pkg.add("Ray")`.  However, for the time being, it's still necessary to install the full build toolchain required to build Ray _and_ our Ray.jl wrappers.

Start by cloning this repo.  The following instructions assume you start from the repository root as the working directory:

```sh
git clone https://github.com/beacon-biosignals/Ray.jl.git
cd Ray.jl
```

### Install dev dependnecies

These are based on the dev setup instructions from upstream Ray but adapted here based on our fork.  These are the _minimal_ dependencies necessary to build the Ray server and the Ray.jl wrappers, and don't include e.g. the dependencies necessary for extras like the Ray dashboard.

#### MacOS

Based on [upstream Ray instructions](https://docs.ray.io/en/releases-2.5.1/ray-contribute/development.html#preparing-to-build-ray-on-macos):

```sh
brew update
brew install wget
brew install bazelisk
```

#### Linux

Based on [upstream Ray instructions](https://docs.ray.io/en/releases-2.5.1/ray-contribute/development.html#preparing-to-build-ray-on-linux), assuming Ubuntu:

```sh
# Add a PPA containing gcc-9 for older versions of Ubuntu.
sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
sudo apt-get update
sudo apt-get install -y build-essential curl gcc-9 g++-9 pkg-config psmisc unzip
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 \
              --slave /usr/bin/g++ g++ /usr/bin/g++-9 \
              --slave /usr/bin/gcov gcov /usr/bin/gcov-9
```

Install [Bazelisk](https://github.com/bazelbuild/bazelisk#readme) by downloading the latest binary for your system from the [releases page](https://github.com/bazelbuild/bazelisk/releases) somewhere on your `$PATH` (like `$HOME/bin/`).  For instance, as of writing this was the latest release for an AMD64 system:

```sh
curl -Lo "$HOME/bin/bazel" "https://github.com/bazelbuild/bazelisk/releases/download/v1.18.0/bazelisk-linux-amd64"
chmod +x "$HOME/bin/bazel"
```

Alternatively, if you have `npm` installed you can install Bazelisk that way:

```sh
npm install -g @bazel/bazelisk
```

### Prepare python environment

We recommend always using the same virtualenv since Bazel can cause unnecessary rebuilds when using different versions of Python.

```sh
python -m venv venv
source venv/bin/activate
# make sure we're using up-to-date version of pip and wheel:
python -m pip install --upgrade pip wheel
```

(These are the same as the [upstream Ray instructions](https://docs.ray.io/en/releases-2.5.1/ray-contribute/development.html#prepare-the-python-environment) but copied here for consistency.)

### Build wrapper

```sh
source venv/bin/activate # if not still activated from previous step

# Build the required libraries
julia --project=ray_julia_jll -e 'using Pkg; Pkg.build(verbose=true)'
```

### Install Ray CLI/server

We currently rely on a patched version of upstream Ray server/CLI that is aware of Julia as a supported language and knows how to launch julia worker processes.  Until these changes are upstreamed to the Ray project, you need to either build from source or install using our custom-build wheels.

#### Install from github release

Find the appropriate binary wheel for your python version and system (currently supported are ARM MacOS, e.g. M1, and AND64/x86_64 linux) from the release page, and install from the release URL.  For instance, to install for Linux for Python 3.9, run this in the appropriate virtual environment:

```sh
pip install https://github.com/beacon-biosignals/ray/releases/download/ray-2.5.1-beacon/ray-2.5.1-cp39-cp39-manylinux2014_x86_64.whl
```

#### Build from source

```sh
# Build the Ray CLI. Based upon these instructions:
# https://docs.ray.io/en/releases-2.5.1/ray-contribute/development.html#building-ray-on-linux-macos-full
python -m pip install --upgrade pip wheel
cd ray_julia_jll/deps/ray/python
pip install -e . --verbose
cd -
```

### Validate installation

Note that because `ray_julia_jll` is not yet released, it's necessary to `Pkg.develop` it; otherwise you'll get errors that Pkg expected it to be registered.

```sh
# Run the tests
julia --project -e 'using Pkg; Pkg.develop(; path="./ray_julia_jll"); Pkg.test()'
```
