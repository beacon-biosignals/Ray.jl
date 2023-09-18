# Building and Publishing JLLs

1. Run the `make.jl` script to build the tarballs for the host platform and julia-version. 
This will create a draft GitHub pre-release for the tag in the `Project.toml`.
The tarball will be uploaded as an asset with a temporary URL.
Note: It is advised you run this within the python virtual environment associated with the root package and set a `GITHUB_TOKEN` environment variable.
```
julia --project -e 'using Pkg; Pkg.develop(path=".."); Pkg.instantiate()'
julia --project make.jl
```
    
2. Once all platforms have uploaded their tarballs, publish the GitHub pre-release (but keep as a pre-release). This will remove the draft, publish the associated tag, and expose the tarball assets via persistent URLs.

3. Create a PR which updates the Artifacts.toml artifacts with the tarball URLs. 
<!-- TODO: The CI workflows for this PR can run successfully and the referenced artifacts will be accessible. -->

4. Once the PR is merged, delete the existing tag and create a new one (with the same version) from the commit you just merged, and then update the GitHub release to point to the new tag.

5. Register the new tag as normal.
