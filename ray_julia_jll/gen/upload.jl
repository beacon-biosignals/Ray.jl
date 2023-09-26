using URIs: URI
using ghr_jll: ghr

include("common.jl")

# Parse "GIT URLs" syntax (URLs and a scp-like syntax). For details see:
# https://git-scm.com/docs/git-clone#_git_urls_a_id_urls_a
# Note that using a Regex like this is inherently insecure with regards to its
# handling of passwords; we are unable to deterministically and securely erase
# the passwords from memory after use.
# TODO: reimplement with a Julian parser instead of leaning on this regex
const URL_REGEX = r"""
^(?:(?<scheme>ssh|git|https?)://)?+
(?:
    (?<user>.*?)
    (?:\:(?<password>.*?))?@
)?
(?<host>[A-Za-z0-9\-\.]+)
(?(<scheme>)
    # Only parse port when not using scp-like syntax
    (?:\:(?<port>\d+))?
    /?
    |
    :?
)
(?<path>
    # Require path to be preceded by '/'. Alternatively, ':' when using scp-like syntax.
    (?<=(?(<scheme>)/|:))
    .*
)?
$
"""x

function parse_git_remote_url(pkg_url)
    m = match(URL_REGEX, pkg_url)
    if m === nothing
        throw(ArgumentError("Package URL is not a valid SCP or HTTP URL: $(pkg_url)"))
    end
    return "https://" * joinpath(m[:host], m[:path])
end

function upload_to_github_release(
    archive_path::AbstractString,
    archive_url::AbstractString,
    commit;
    kwargs...
)
    return upload_to_github_release(archive_path, parse(URI, archive_url), commit; kwargs...)
end

# TODO: Does this work properly with directories?
function upload_to_github_release(archive_path::AbstractString, archive_uri::URI, commit; kwargs...)
    # uri = parse(URI, artifact_url)
    if archive_uri.host != "github.com"
        throw(ArgumentError("Artifact URL is not for github.com: $(archive_uri)"))
    end

    m = match(GH_RELEASE_ASSET_PATH_REGEX, archive_uri.path)
    if m === nothing
        throw(ArgumentError(
            "Artifact URL is not a GitHub release asset path: $(archive_uri)"
        ))
    end

    upload_to_github_release(m[:owner], m[:repo_name], commit, m[:tag], archive_path; kwargs...)

    return nothing
end

function upload_to_github_release(owner, repo_name, commit, tag, path; token=ENV["GITHUB_TOKEN"])
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

    run(cmd)
end

if abspath(PROGRAM_FILE) == @__FILE__

    isdir(TARBALL_DIR) || error("$TARBALL_DIR does not exist")
    !haskey(ENV, "GITHUB_TOKEN") && error("\"GITHUB_TOKEN\" environment variable required.")

    # check that contents are tarballs with correct filename
    all(t -> !isnothing(match(TARBALL_REGEX, t)), readdir(TARBALL_DIR))

    pkg_http_url = parse_git_remote_url(PKG_URL)
    artifact_url = "$(pkg_http_url)/releases/download/$TAG"
    branch = LibGit2.with(LibGit2.branch, LibGit2.GitRepo(REPO_PATH))

    @info "Uploading tarballs to $artifact_url"
    try
        upload_to_github_release(TARBALL_DIR, artifact_url, branch)
    catch e
        # ghr() already prints an error message with diagnosis
        @debug "Caught exception $(sprint(showerror, e, catch_backtrace()))"
    end

end
