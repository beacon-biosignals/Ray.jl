# Building Artifacts

For Ray.jl releases we provide pre-built binary artifacts to allow for [easy installation](./installation.md) of the Ray.jl package. Currently, we need to build a custom Ray CLI which includes Julia language support and platform specific shared libraries for `ray_julia_jll`.

### Ray CLI/Server

Follow [the instructions](https://github.com/beacon-biosignals/ray/blob/beacon-main/python/README-building-wheels.md) outlined in the Beacon fork of Ray.

### Artifacts

The `ray_julia` artifacts are hosted via [GitHub releases](https://github.com/beacon-biosignals/Ray.jl/releases) and will be downloaded automatically for any supported platform which installs Ray.jl from a tag.

However, the artifacts are only associated with tagged releases of Ray.jl. 
If you are working off the `main` branch, or developing Ray.jl locally, you will need to [build Ray.jl](./developer-guide.md#build-rayjl) yourself. 
This will also update your `Overrides.toml` to reference the binaries you have built.

To update the Ray.jl artifacts for a new release simply open a PR which bumps the Ray.jl version in the `Project.toml` and includes any other required changes.
The Julia CI jobs created by this PR will build the artifacts required to make a new release.
Upon merging the PR with `main` a new tag will be created and the artifacts will be uploaded to a GitHub Pre-Release, which will be converted as a full Release once the CI for the tag passes.
