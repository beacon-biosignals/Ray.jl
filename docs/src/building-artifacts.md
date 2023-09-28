# Building Artifacts

For Ray.jl releases we provide pre-built binary artifacts to allow for [easy installation](./installation.md) of the Ray.jl package. Currently, we need to build a custom Ray CLI which includes Julia language support and platform specific shared libraries for `ray_julia_jll`.

### Ray CLI/Server

Follow [the instructions](https://github.com/beacon-biosignals/ray/blob/beacon-main/python/README-building-wheels.md) outlined in the Beacon fork of Ray.

### Artifacts

The `ray_julia` artifacts are hosted via [GitHub releases](https://github.com/beacon-biosignals/Ray.jl/releases) and will be downloaded automatically for any supported platform. To upate the artifacts, perform the following steps:

1. Update the Ray.jl version in the `Project.toml`

2. Navigate to the `build` directory

3. Run the `build_tarballs.jl` script to build the tarball for the host platform for the Julia version used. Builds are required for the platform triplets `x86_64-linux-gnu` and `aarch64-apple-darwin`. It is advised you run this within the python virtual environment associated with the Ray.jl package to avoid unnecessary Bazel rebuilds.  Note: re-running this script _will overwrite_ an existing tarball for this version of Ray.jl.

   ```sh
   source ../venv/bin/activate
   julia --project -e 'using Pkg; Pkg.instantiate()'
   julia --project build_tarballs.jl
   ```

4. Run the `upload_tarballs.jl` script to publish the tarball(s) as asset(s) of a GitHub pre-release, which requires a `GITHUB_TOKEN` environment variable. Note: you can run this script after building each tarball, or after you've built them all. Rerunning it will only upload new tarballs and skip any that have already been published.

   ```sh
   read -s GITHUB_TOKEN
   export GITHUB_TOKEN
   julia --project upload_tarballs.jl
   ```

5. Once all assets are uploaded, checkout a new branch (based off of `main`) and run the `bind_artifacts.jl`. This will modify the local `Artifacts.toml` with the artifact(s) associated with the Ray.jl version specified in the Project.toml. After running this you should commit and push the changes to a new PR.

   ```sh
   julia --project bind_artifacts.jl
   ```

6. Once that PR is merged, delete the existing tag (which will convert the release to a draft) and create a new one (with the same version) from the commit you just merged.
Then update the GitHub release to point to the new tag.

7. Register the new tag as normal with JuliaRegistrator.
