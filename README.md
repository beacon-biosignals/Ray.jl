# Ray.jl

The `ray_julia_jll` is the Julia C++ wrapper that interfaces with the Ray.io project's shared core worker library.

At the moment the package requires that the shared libraries are built directly on the host system and does not provide any precreated cross-compiled libraries. We hope to turn this package into a full fledged JLL but this direct build process will work as we experiment with interfacing with the Ray core worker C++ interface.

## FAQ

### Why am I seeing "expected `ray_julia_jll` to be registered when I use Ray.jl?

You need to `Pkg.develop` _both_ Ray.jl _and_ `ray_julia_jll` in any project that uses Ray.jl.

Currently neither Ray.jl nor the `ray_julia_jll` package are registered since they're under heavy development, and because automated builds of the JLL are not possible using the existing Julia BinaryBuilder infrastructure.

### How do I start/stop the ray backend?

Make sure the [appropriate environment](#prepare-python-environment) (`venv` or `conda`-managed) is active (wherever you [`pip install`ed Ray](#install-ray-cliserver)) and then do

```sh
ray start --head
```

to start and

```sh
ray stop
```

to stop.

### Where can I find log files?

The directory `/tmp/ray/session_latest/logs` contains logs for the current or last ran ray backend.

The `raylet.err` is particularly informative when debugging workers failing to start, since error output before connecting to the Ray server is printed there.

Driver logs generated by Ray are printed in `julia-core-driver-$(JOBID)_$(PID).log`, and julia worker logs are in `julia_worker_$(PID).log` (although this may change).

### My workers aren't starting, help?

Check the raylet logs in `/tmp/ray/session_latest/logs/raylet.err`.  If you see something about Revise (or another package) not being found, make sure you're not doing something like unconditionally `using Revise` in your `~/.julia/config/startup.jl` file; it's generally a good idea to wrap any `using`s in your startup.jl in a `try`/`catch` block [like the Revise docs recommend](https://timholy.github.io/Revise.jl/stable/config/#Using-Revise-by-default-1).

### Why is cluster startup failng with `AssertionError: pydantic.dataclasses.dataclass only supports init=False`?

Ray versions before 2.6 only support pydantic 1.x; downgrade with `pip install "pydantic<2"`.

## Setup

Ultimately our aim is to make installing Ray.jl as simple as `Pkg.add("Ray")`. However, for the time being, it's still necessary to install the full build toolchain required to use Ray _and_ our Ray.jl wrappers.

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

### Install Ray CLI/server

We currently rely on a patched version of upstream Ray server/CLI that is aware of Julia as a supported language and knows how to launch julia worker processes.
Until these changes are upstreamed to the Ray project, you need to either [build from source](https://github.com/beacon-biosignals/ray/blob/beacon-main/python/README-building-wheels.md) or install using our custom-built wheels.

NOTE: make sure you've [activated the appropriate virtual environment](#prepare-python-environment) where you want to install the Ray CLI!

#### Install from github release

Find the appropriate binary wheel for your python version and system (currently supported are macOS ARM64 (M1), and Linux AMD64/x86_64) from the [releases page](https://github.com/beacon-biosignals/ray/releases), and install from the release URL.
For instance, to install Ray CLI for Linux running Python 3.9, run this command in the appropriate virtual environment:

```sh
pip install -U "ray[default] @ https://github.com/beacon-biosignals/ray/releases/download/ray-2.5.1+1/ray-2.5.1-cp39-cp39-manylinux2014_x86_64.whl"
```

Replace the `https://` URL with the approriate release asset URL.
Note: you may also need to increment the build number to get the latest wheels.

(Installing `ray[default]` will also install additional dependencies that are necessary for the cluster status server and dashboard)

#### Build from source

Follow [the instructions](https://github.com/beacon-biosignals/ray/blob/beacon-main/python/README-building-wheels.md) outlined in the Beacon fork of Ray.


### JLL Artifacts

The `ray_julia_jll` artifacts are hosted in [GitHub releases](https://github.com/beacon-biosignals/Ray.jl/releases) and will be downloaded automatically for any supported platform when calling `Pkg.build()`.
To rebuild the artifacts, you can follow the [build instructions](./ray_julia_jll/gen/README.md).


### Validate installation

Note that because `ray_julia_jll` is not yet released, it's necessary to `Pkg.develop` it; otherwise you'll get errors that Pkg expected it to be registered.

```sh
# Run the tests
julia --project -e 'using Pkg; Pkg.develop(; path="./ray_julia_jll"); Pkg.test()'
```
