# Building Artifacts

For Ray.jl releases we provide pre-built binary artifacts to allow for [easy installation](./installation.md) of the Ray.jl package. Currently, we need to build a custom Ray CLI which includes Julia language support and platform specific shared libraries for `ray_julia_jll`.

### Ray CLI/Server

Follow [the instructions](https://github.com/beacon-biosignals/ray/blob/beacon-main/python/README-building-wheels.md) outlined in the Beacon fork of Ray.

### Artifacts

The `ray_julia` artifacts are hosted via [GitHub releases](https://github.com/beacon-biosignals/Ray.jl/releases) and will be downloaded automatically for any supported platform (currently `x86_64-linux-gnu` and `aarch64-apple-darwin`).

At the moment updating these artifacts is semi-automated in that the GitHub actions builds the `x86_64-linux-gnu` artifacts but builds for `aarch64-apple-darwin` must be performed manually on a compatible host system.

To update the artifacts, ensure you are running on macOS using Apple Silicon (`aarch64-apple-darwin`) and have first have already [built Ray.jl](./developer-guide.md#build-rayjl) successfully. Then perform the following steps:

1. Create a new branch (based off of `origin/HEAD`) and update the Ray.jl version in the `Project.toml` file. Commit and push this change to a new PR.

2. Navigate to the `build` directory

3. Run the `build_tarballs.jl` script builds the tarball for the host platform and Julia version used. Using the `--all` flag builds the host platform tarballs for all supported Julia versions. When running this on `aarch64-apple-darwin` we'll build those artifacts locally and then use `--fetch` to retrieve GitHub Action built artifacts for `x86_64-linux-gnu`. It is advised you run this within the Python virtual environment associated with the Ray.jl package to avoid unnecessary Bazel rebuilds. Re-running this script _will overwrite_ an existing tarball for this version of Ray.jl.

   ```sh
   julia --project -e 'using Pkg; Pkg.instantiate()'

   # Cleanup any tarballs from previous builds
   rm -rf tarballs

   # Build the host tarballs. When run on Apple Silicon this builds the aarch64-apple-darwin tarballs
   source ../venv/bin/activate
   julia --project build_tarballs.jl --all

   # Fetches the x86_64-linux-gnu tarballs from GitHub Actions (may need to wait)
   read -s GITHUB_TOKEN
   export GITHUB_TOKEN
   julia --project build_tarballs.jl --fetch
   ```

4. Run the `upload_tarballs.jl` script to publish the tarballs as assets of a GitHub pre-release, which requires a `GITHUB_TOKEN` environment variable. Re-running this script will only upload new tarballs and skip any that have already been published.

   ```sh
   read -s GITHUB_TOKEN
   export GITHUB_TOKEN
   julia --project upload_tarballs.jl
   ```

5. Run `bind_artifacts.jl` to modify local `Artifacts.toml` with the artifacts associated with the Ray.jl version specified in the `Project.toml`. After running this you should commit and push the changes to the PR you created in Step 1.

   ```sh
   julia --project bind_artifacts.jl

   git commit -a -m "Update Artifacts.toml"
   git push origin
   ```

6. Merge the PR. If the PR becomes out of date with the default branch then you will need to repeat steps 3-6 to ensure that the tarballs include the current changes. In some scenarios re-building the tarballs may be unnecessary such as a documentation only change. If in doubt re-build the tarballs.

7. After the PR is merged, delete the existing tag (which will convert the release to a draft) and create a new one (with the same version) from the commit you just merged.
Then update the GitHub release to point to the new tag.

   ```sh
   git tag -d $tag
   git push origin :$tag
   git tag $tag

   # Update GitHub Release to point to the updated tag
   ```

8. Register the new tag as normal with JuliaRegistrator.
