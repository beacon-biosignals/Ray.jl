# Building and Publishing JLLs

1. Run the `make.jl` script to build the tarballs for the host platform and julia-version. 
This will create a GitHub pre-release for the tag in the `Project.toml`.
Note: It is advised you run this within the python virtual environment associated with the root package and set a `GITHUB_TOKEN` environment variable.
```
julia --project -e 'using Pkg; Pkg.develop(path=".."); Pkg.instantiate()'
julia --project make.jl
```

3. Once all platforms have uploaded their tarballs, create a PR which updates the Artifacts.toml artifacts with the tarball URLs. 
<!-- TODO: The CI workflows for this PR can run successfully and the referenced artifacts will be accessible. -->

4. Once the PR is merged, delete the existing tag (this will convert the release to a draft) and create a new one (with the same version) from the commit you just merged.
Then update the GitHub release to point to the new tag.

5. Register the new tag as normal.
