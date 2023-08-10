# run this script in the `docs` project to fix the doctests if they are out of date
# carefully review the changes before committing!

# One needs to be careful because `fix=true` will edit the source to fix
# the doctests, and it's good to separate those changes so you can check
# they are correct (and be easily revertable if they do something wrong).

using Documenter, Ray

DocMeta.setdocmeta!(Ray, :DocTestSetup, :(using Ray);
                    recursive=true)

if get(ENV, "CI", "false") == "true" || success(`git diff --quiet`)
    if ismissing(get(ENV, "AWS_PROFILE", missing))
        @warn """You may need to set `ENV["AWS_PROFILE"] = ray_core_worker_julia_jll-ci` in order to successfully run the doctests"""
    end
    doctest(Ray; fix=true)
else
    error("Git repo dirty; commit changes before fixing doctests.")
end
