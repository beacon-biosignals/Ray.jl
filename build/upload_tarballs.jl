using URIs: URI
using ghr_jll: ghr

include("common.jl")

function upload_to_github_release(archive_path::AbstractString,
                                  archive_url::AbstractString,
                                  commit;
                                  kwargs...)
    return upload_to_github_release(archive_path, parse(URI, archive_url), commit;
                                    kwargs...)
end

# TODO: Does this work properly with directories?
function upload_to_github_release(archive_path::AbstractString, archive_uri::URI, commit;
                                  kwargs...)
    # uri = parse(URI, artifact_url)
    if archive_uri.host != "github.com"
        throw(ArgumentError("Artifact URL is not for github.com: $(archive_uri)"))
    end

    m = match(GH_RELEASE_ASSET_PATH_REGEX, archive_uri.path)
    if m === nothing
        throw(ArgumentError("Artifact URL is not a GitHub release asset path: $(archive_uri)"))
    end

    upload_to_github_release(m[:owner], m[:repo_name], commit, m[:tag], archive_path;
                             kwargs...)

    return nothing
end

function upload_to_github_release(owner, repo_name, commit, tag, path;
                                  token=ENV["GITHUB_TOKEN"])

    # Based on: https://github.com/JuliaPackaging/BinaryBuilder.jl/blob/d40ec617d131a1787851559ef1a9f04efce19f90/src/AutoBuild.jl#L487
    # TODO: Passing in a directory path uploads multiple assets
    # TODO: Would be nice to perform parallel uploads
    cmd = ```
        $(ghr()) \
        -owner $owner \
        -repository $repo_name \
        -commitish $commit \
        -token $token \
        -n $tag \
        -prerelease \
        $tag $path
    ```

    try
        run(cmd)
    catch e
        # ghr() already prints an error message with diagnosis
        @debug "Caught exception $(sprint(showerror, e, catch_backtrace()))"
    end

    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    isdir(TARBALL_DIR) || error("$TARBALL_DIR does not exist")
    !haskey(ENV, "GITHUB_TOKEN") && error("\"GITHUB_TOKEN\" environment variable required.")

    # check that contents are tarballs with correct filename
    for t in readdir(TARBALL_DIR)
        m = match(TARBALL_REGEX, t)
        !isnothing(m) || error("Unexpected file found: tarballs/$t")
        "v$(m[:jll_version])" == TAG || error("Unexpected JLL version: tarballs/$t")
    end

    artifact_url = gen_artifact_url(; repo_url=REPO_HTTPS_URL, tag=TAG, filename="")
    branch = LibGit2.with(LibGit2.branch, LibGit2.GitRepo(REPO_PATH))

    @info "Uploading tarballs to $artifact_url"
    upload_to_github_release(TARBALL_DIR, artifact_url, branch)
end
