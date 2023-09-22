# Building and Publishing JLLs

1. Run the `make.jl` script to build the tarball for the host platform and a given julia-version.
Builds are required for `linux x86_64` and `macos-arm64`, and julia `v1.8.0` and `v1.9.0`.
It is advised you run this within the python virtual environment associated with the root package and set a `GITHUB_TOKEN` environment variable.
Note: rerunning this script _will overwrite_ an existing tarball.
```
julia --project -e 'using Pkg; Pkg.develop(path=".."); Pkg.instantiate()'
julia --project make.jl
```

2. Once a tarball has been built you can run the `upload.jl` script.
This will create a GitHub pre-release for the tag in the `Project.toml` (if one does not already exist) and publish each tarball in "gen/tarballs" to the release page.
Note: reruning this script _will not overwrite_ an existing asset.
```
julia --project upload.jl
```

3. Once all assets are uploaded, create a PR which updates the Artifacts.toml artifacts with the tarball URLs. 
<!-- TODO: The CI workflows for this PR can run successfully and the referenced artifacts will be accessible. -->

4. Once that PR is merged, delete the existing tag (which will convert the release to a draft) and create a new one (with the same version) from the commit you just merged.
Then update the GitHub release to point to the new tag.

5. Register the new tag as normal.
