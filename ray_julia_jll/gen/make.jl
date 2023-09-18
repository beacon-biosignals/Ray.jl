using Base: SHA1, BinaryPlatforms
using CodecZlib: GzipCompressorStream, GzipDecompressorStream
using LibGit2: LibGit2
using Pkg
using Pkg.Types: read_project
using SHA: sha256
using Tar: Tar
using URIs: URI
using ghr_jll: ghr

const ASSETS = Set(["external",
                    "julia_core_worker_lib.so-2.params",
                    "_objs",
                    "julia_core_worker_lib.so.runfiles_manifest",
                    "julia_core_worker_lib.so",
                    "julia_core_worker_lib.so.runfiles"])

const GH_RELEASE_ASSET_PATH_REGEX = r"""
    ^/(?<owner>[^/]+)/(?<repo_name>[^/]+)/
    releases/download/
    (?<tag>[^/]+)/(?<file_name>[^/]+)$
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

function create_tarball(dir, tarball)
    return open(GzipCompressorStream, tarball, "w") do tar
        Tar.create(dir, tar)
    end
end

# Compute the Artifact.toml `git-tree-sha1`.
function tree_hash_sha1(tarball_path)
    return open(GzipDecompressorStream, tarball_path, "r") do tar
        SHA1(Tar.tree_hash(tar))
    end
end

# Compute the Artifact.toml `sha256` from the compressed archive.
function sha256sum(tarball_path)
    return open(tarball_path, "r") do tar
        bytes2hex(sha256(tar))
    end
end

function remote_url(repo_root::AbstractString, name::AbstractString="origin")
    return LibGit2.with(LibGit2.GitRepo(repo_root)) do repo
        LibGit2.with(LibGit2.lookup_remote(repo, name)) do remote
            LibGit2.url(remote)
        end
    end
end

function upload_to_github_release(
    archive_path::AbstractString,
    archive_url::AbstractString,
    commit;
    kwargs...
)
    return upload_to_github_release(archive_path, parse(URI, artifact_url), commit; kwargs...)
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
        $tag $path
    ```

    run(cmd)
end

if abspath(PROGRAM_FILE) == @__FILE__

    # Check for this now before we spend any time building the JLL
    !haskey(ENV, "GITHUB_TOKEN") && error("\"GITHUB_TOKEN\" environment variable required.")

    repo_path = abspath(joinpath(@__DIR__, "..", ".."))
    pkg_url = remote_url(repo_path)

    # Build JLL
    @info "Building ray_julia_jll on $host"
    Pkg.build("ray_julia_jll"; verbose=true)
    compiled_dir = joinpath(repo_path, "ray_julia_jll", "deps", "bazel-bin")

    # Limit what we include in tarball
    compiled_assets = Set(readdir(compiled_dir))
    if compiled_assets != ASSETS
        throw(ArgumentError("Unexpected JLL assets found: $compiled_assets"))
    end

    # Read Project.toml
    jll_project_toml = joinpath(repo_path, "ray_julia_jll", "Project.toml")
    jll_project = read_project(jll_project_toml)
    jll_version = jll_project.version

    host_triplet = BinaryPlatforms.triplet(host)
    tarball_name = "ray_julia.v$jll_version.$host_triplet.tar.gz"

    @info "Creating tarball $tarball_name"
    tarball_path = joinpath(tempdir(), tarball_name)
    create_tarball(readlink(compiled_dir), tarball_path)

    m = match(URL_REGEX, pkg_url)
    if m === nothing
        throw(ArgumentError("Package URL is not a valid SCP or HTTP URL: $(pkg_url)"))
    end

    pkg_http_url = "https://" * joinpath(m[:host], m[:path])
    tag = "v$(jll_version)"
    artifact_url = "$(pkg_http_url)/releases/download/$(tag)/$(basename(tarball_path))"

    upload_to_github_release(tarball_path, artifact_url, branch)
end
