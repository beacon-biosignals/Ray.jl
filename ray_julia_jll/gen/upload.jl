using LibGit2: LibGit2
using Pkg.Types: read_project
using URIs: URI
using ghr_jll: ghr

const TARBALL_DIR = joinpath(@__DIR__, "tarballs")

const TARBALL_REGEX = r"""
    ^ray_julia.v(?<jll_version>([0-9]\.){3})
    (?<triplet>[a-z, 0-9, \-, \_,]+)
    -julia_version\+(?<julia_version>([0-9]\.){3})
    tar.gz$
    """x

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

const GH_RELEASE_ASSET_PATH_REGEX = r"""
    ^/(?<owner>[^/]+)/(?<repo_name>[^/]+)/
    releases/download/
    (?<tag>[^/]+)/(?<file_name>[^/]+)$
    """x

function remote_url(repo_root::AbstractString, name::AbstractString="origin")
    return LibGit2.with(LibGit2.GitRepo(repo_root)) do repo
        LibGit2.with(LibGit2.lookup_remote(repo, name)) do remote
            LibGit2.url(remote)
        end
    end
end

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

    # The `ghr` utility uses the local file name for the release asset. In order to have
    # have the asset match the specified URL we'll temporarily rename the file.
    org_archive_name = nothing
    if basename(archive_path) != m[:file_name]
        org_archive_name = basename(archive_path)
        archive_path = mv(archive_path, joinpath(dirname(archive_path), m[:file_name]))
    end

    upload_to_github_release(m[:owner], m[:repo_name], commit, m[:tag], archive_path; kwargs...)

    # Rename the archive back to the original name
    if org_archive_name !== nothing
        mv(archive_path, joinpath(dirname(archive_path), org_archive_name))
    end

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

    # Check for this now before we spend any time building the JLL
    !haskey(ENV, "GITHUB_TOKEN") && error("\"GITHUB_TOKEN\" environment variable required.")

    repo_path = abspath(joinpath(@__DIR__, "..", ".."))
    pkg_url = remote_url(repo_path)
    pkg_http_url = parse_git_remote_url(pkg_url)

    # Read Project.toml
    jll_project_toml = joinpath(repo_path, "ray_julia_jll", "Project.toml")
    jll_project = read_project(jll_project_toml)
    jll_version = jll_project.version
    tag = "v$(jll_version)"

    for tarball in readdir(TARBALL_DIR)

        m = match(TARBALL_REGEX, tarball)
        isnothing(m) && continue

        artifact_url = "$(pkg_http_url)/releases/download/$(tag)/$tarball"
        branch = LibGit2.with(LibGit2.branch, LibGit2.GitRepo(repo_path))
        @info "Uploading $tarball to $artifact_url"
        upload_to_github_release(joinpath(TARBALL_DIR, tarball), artifact_url, branch)
    end

end
