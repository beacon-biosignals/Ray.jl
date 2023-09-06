# Ray.jl

The `ray_julia_jll` is the Julia C++ wrapper that interfaces with the Ray.io project's shared core worker library.

At the moment the package requires that the shared libraries are built directly on the host system and does not provide any precreated cross-compiled libraries. We hope to turn this package into a full fledged JLL but this direct build process will work as we experiment with interfacing with the Ray core worker C++ interface.

## Example

```sh
# We recommend always using the same virtualenv as Bazel can cause unnecessary rebuilds when
# using different versions of Python.
python3 -m venv venv
source venv/bin/activate

# Build the required libraries
julia --project=ray_julia_jll -e 'using Pkg; Pkg.build(verbose=true)'

# Build the Ray CLI. Based upon these instructions:
# https://docs.ray.io/en/releases-2.5.1/ray-contribute/development.html#building-ray-on-linux-macos-full
python -m pip install --upgrade pip wheel
cd ray_julia_jll/deps/ray/python
pip install -e . --verbose
cd -

# Run the tests
julia --project -e 'using Pkg; Pkg.test()'
```

## Sources

The tarballs for `ray_julia_jll.jl` have been built from these sources:

* ray v2.5.1
* libcxxwrap_julia
