# Building and Publishing JLLs

Run the `make.jl` script to build `ray_julia_jll` associated with a given version of julia and host platform.
The artifacts are published to a public S3 bucket and the Artifacts.toml is updated.
Rerunning for the same host/version will error unless the `ray_julia_jll` version has changed.

It is advised you run this within the python virtual environment associated with the root package and use a suitable role:
```
julia --project -e 'using Pkg; Pkg.develop(path="..")'
AWS_PROFILE="role" julia --project make.jl
```
