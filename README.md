# `ray_core_worker_julia_jll.jl` (v0.1.0)

This is a manually created package as a stop-gap until we figure out how to build cross-compilation binaries with Bazel in BinaryBuilder.

Run the `build/build.sh` script to build JLL package from scratch and link it to the Artifacts.toml.
This is to enable workaround local development until we publically publish the package as it's not very feasible to pull Artifacts from private repositories:
https://discourse.julialang.org/t/how-to-configure-an-artifact-to-use-a-header-during-package-download/96057/2

```sh
./build/build.sh

ray start --head
julia --project wrapper.jl
ray stop
```

Run `./build/clean.sh` to delete all files created by the build script.

Make sure you have ray installed:
```sh
python3 -m venv venv
source venv/bin/activate
pip install -U "ray[default]==2.5.1" "pydantic<2"
```

## Sources

The tarballs for `ray_core_worker_julia_jll.jl` have been built from these sources:

* ray v2.5.1
* libcxxwrap_julia

## Platforms

`ray_core_worker_julia.jl` is available for the following platforms:

* `Linux x86_64 {libc=glibc}` (`x86_64-linux-gnu`)
