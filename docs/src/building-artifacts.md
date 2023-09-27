# Building Artifacts

For Ray.jl releases we provide pre-built binary artifacts to allow for [easy installation](./installation.md) of the Ray.jl package. Currently, we need to build a custom Ray CLI which includes Julia language support and platform specific shared libraries for `ray_julia_jll`.

### Ray CLI/Server

Follow [the instructions](https://github.com/beacon-biosignals/ray/blob/beacon-main/python/README-building-wheels.md) outlined in the Beacon fork of Ray.

### JLL Artifacts

The `ray_julia_jll` artifacts are hosted in [GitHub releases](https://github.com/beacon-biosignals/Ray.jl/releases) and will be downloaded automatically for any supported platform. To rebuild the artifacts, you can follow the [build instructions](https://github.com/beacon-biosignals/Ray.jl/blob/main/build/README.md).
