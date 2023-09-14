# Building and Publishing JLLs

Run the `make.jl` script with a version of `julia` on given host to build and publish `ray_julia_jll` artifacts to the [`Ray.jl` Github Relases page](https://github.com/beacon-biosignals/Ray.jl/releases).
Rerunning for the same host/version will error unless the `ray_julia_jll` version has changed.

```
julia --project -e 'using Pkg; Pkg.develop(path=".."); include("make.jl")'
```
