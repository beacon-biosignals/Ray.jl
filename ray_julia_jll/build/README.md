# Building and Publishing JLLs

1. Run the `build_tarballs.jl` script to build the tarball for the host platform and a given julia-version.
Builds are required for `linux x86_64` and `macos-arm64` on julia `v1.8` and `v1.9`.
It is advised you run this within the python virtual environment associated with the root package.
Note: rerunning this script _will overwrite_ an existing tarball.

```sh
julia --project -e 'using Pkg; Pkg.instantiate()'
julia --project build_tarballs.jl
```

2. Run the `upload_tarballs.jl` script to publish the tarball(s) as asset(s) of a GitHub pre-release, which requires a `GITHUB_TOKEN` environment variable.
Note: you can run this script after building each tarball, or after you've built them all. Rerunning it will only upload new tarballs and skip any that have already been published.

```sh
read -s GITHUB_TOKEN
export GITHUB_TOKEN
julia --project upload_tarballs.jl
```

3. Once all assets are uploaded, checkout a new branch (based off of `main`) and run the `bind_artifacts.jl`. This will modify the local `Artifacts.toml` with the new artifact(s). After running this you should commit and push the changes to a new PR.

```sh
julia --project bind_artifacts.jl
```
<!-- TODO: The CI workflows for this PR can run successfully and the referenced artifacts will be accessible. -->

4. Once that PR is merged, delete the existing tag (which will convert the release to a draft) and create a new one (with the same version) from the commit you just merged.
Then update the GitHub release to point to the new tag.

5. Register the new tag as normal with JuliaRegistrator.
