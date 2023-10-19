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
Once the PR has been merged into `main` and the CI has passed you must trigger the ["Publish Release" GitHub Action](https://github.com/beacon-biosignals/Ray.jl/actions/workflows/Pre_release.yml) and the following actions will be run in the workflow:
1. Download the various artifacts for supported platforms from `main`.
2. Generate the `Artifacts.toml` bindings and commit them.
3. Create a new tag and GitHub pre-release which includes the artifacts as assets.

The creation of the tag will trigger the "Artifacts CI" workflow which is responsible for verifying the generated artifacts work. 
It will then promote the GitHub pre-release to a full release once those checks pass.
