# Ray.jl

## Setup instructions

**This package is under heavy development!**

You should probably `] dev` this package somewhere, rather than `] add`ing it.
These instructions assume you've cloned this repo locally and are in this
directory:

```sh
git clone https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl && \
  cd ray_core_worker_julia_jll.jl
```

### Clone patched Ray repo

This happens automatically when you build but may be better to do it manually:

```sh
git clone https://github.com/beacon-biosignals/ray deps/ray
```

### Build Ray server/CLI

Enter the ray source root, setup the venv, and build the CLI/server (this will
take quite a while, half an hour plus)

```sh
pushd deps/ray
python3 -m venv venv
source venv/bin/activate
python -m pip install --upgrade pip wheel
pushd python && pip install -e . --verbose && popd
popd
```

For more details, consult the instructions on Ray development builds here:
https://docs.ray.io/en/latest/ray-contribute/development.html#building-ray-on-linux-macos-full

Pay special attention to the dependencies that are required:
- python3 (including venv and dev tooling which are separate packages on ubuntu)
- [bazelisk](https://github.com/bazelbuild/bazelisk) (launcher/installer for
  bazel build system)
- gcc version 9

Also pay special attention to the requirement for a virtual environment with an
updated pip/wheel installed:
https://docs.ray.io/en/latest/ray-contribute/development.html#prepare-the-python-environment

**In general things will go smoother if you do everything with this venv
activated, although it's not a hard requirement**

Skip the "Building Ray (Python only)" section, this happens during the full
build.

You can probably also skip the `npm` steps unless you need to use the dashboard.

### Build the jll wrapper

```sh 
julia --project -e 'using Pkg; Pkg.build(; verbose=true)'
```

This will probably _also_ take quite a while, since bazel does not seem to
re-use the build cache from the CLI build even though there's a lot of overlap
there.  But once it's done, the cache should give you pretty good re-build
performance if you do need to tweak the JLL wrappers at all.

### Start a local Ray server

This step needs to be done _only once_ while your machine is up (i.e., until you
shutdown/reboot):

```sh
ray start --head
```

Now you should be able to do

```julia
using Ray
Ray.init()
```
