# Building Artifacts

For Ray.jl releases we provide pre-built binary artifacts to allow for [easy installation](./installation.md) of the Ray.jl package. Currently, we need to build a custom Ray CLI which includes Julia language support and platform specific shared libraries for `ray_julia_jll`.

### Ray CLI/Server

Follow [the instructions](https://github.com/beacon-biosignals/ray/blob/beacon-main/python/README-building-wheels.md) outlined in the Beacon fork of Ray.

### Artifacts

The `ray_julia` artifacts are hosted via [GitHub releases](https://github.com/beacon-biosignals/Ray.jl/releases) and will be downloaded automatically for any supported platform which installs Ray.jl.

To update the Ray.jl artifacts for a new release perform the following steps:

1. Create a new branch (based off of `origin/HEAD`) and bump the Ray.jl version in the `Project.toml` file. Commit and push this change to a new PR. The Julia CI jobs created by this PR will build the artifacts required to make a new release.

2. Wait for the CI workflows to complete for the created PR.

3. Navigate to the `build` directory

4. Run the `build_tarballs.jl --fetch` script to fetch the GitHub workflow tarballs for all of the required platforms and Julia versions.

   ```sh
   julia --project -e 'using Pkg; Pkg.instantiate()'

   # Cleanup any tarballs from previous builds
   rm -rf tarballs

   # Fetches the tarballs from GitHub Actions artifacts (may need to wait on CI)
   read -s GITHUB_TOKEN
   export GITHUB_TOKEN
   julia --project build_tarballs.jl --fetch
   ```

5. Run the `upload_tarballs.jl` script to publish the tarballs as assets of a GitHub pre-release. Re-running this script will only upload new tarballs and skip any that have already been published.

   ```sh
   read -s GITHUB_TOKEN
   export GITHUB_TOKEN
   julia --project upload_tarballs.jl
   ```

6. Run `bind_artifacts.jl` to modify local `Artifacts.toml` with the artifacts associated with the Ray.jl version specified in the `Project.toml`. After running this you should commit and push the changes to the PR you created in Step 1.

   ```sh
   julia --project bind_artifacts.jl

   git commit -a -m "Update Artifacts.toml"
   git push origin
   ```

7. Merge the PR. If the PR becomes out of date with the default branch then you will need to repeat steps 3-6 to ensure that the tarballs include the current changes. In some scenarios re-building the tarballs may be unnecessary such as a documentation only change. If in doubt re-build the tarballs.

8. After the PR is merged, delete the existing tag (which will convert the release to a draft) and create a new one (with the same version) from the commit you just merged. Then update the GitHub release to point to the new tag.

   ```sh
   git tag -d $tag
   git push origin :$tag
   git tag $tag

   # Update GitHub Release to point to the updated tag
   ```

9. Register the new tag as normal with JuliaRegistrator.
