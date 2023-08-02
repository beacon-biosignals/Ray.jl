# `ray_core_worker_julia_jll.jl`

The `ray_core_worker_julia_jll` is the Julia C++ wrapper that interfaces with the Ray.io project's shared core worker library. 

At the moment the package requires that the shared libraries are built directly on the host system and does not provide any precreated cross-compiled libraries. We hope to turn this package into a full fledged JLL but this direct build process will work as we experiment with interfacing with the Ray core worker C++ interface.

## Example

```sh
# Build the required libraries
julia --project -e 'using Pkg; Pkg.build(verbose=true)'

ray start --head
julia --project wrapper.jl
ray stop
```

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
