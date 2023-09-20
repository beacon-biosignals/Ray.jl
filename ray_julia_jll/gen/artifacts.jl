using Base: SHA1, BinaryPlatforms
using CodecZlib: GzipCompressorStream, GzipDecompressorStream
using CURL_jll
using jq_jll
using LibGit2: LibGit2
using Pkg.Artifacts: bind_artifact!
using Pkg.Types: read_project
using SHA: sha256
using Tar
using wget_jll

const TRIPLET_REGEX = r"""
    ^ray_julia.v(?<jll_version>([0-9]\.){3})
    (?<triplet>[a-z, 0-9, \-, \_,]+)
    -julia_version\+(?<julia_version>([0-9]\.){3})
    tar.gz$
    """x

const GH_RELEASE_ASSET_PATH_REGEX = r"""
    ^/(?<owner>[^/]+)/(?<repo_name>[^/]+)/
    releases/download/
    (?<tag>[^/]+)/(?<file_name>[^/]+)$
    """x

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

function get_release_asset_urls(jll_version)
    # TODO: parse URL from pkg_url
    assets_url = "https://api.github.com/repos/beacon-biosignals/Ray.jl/releases/tags/v$(jll_version)"
    io = IOBuffer()
    run(pipeline(`$(curl()) $assets_url`, `$(jq()) -r '.assets[].browser_download_url'`, io))
    assets = split(String(take!(io)), "\n"; keepempty=false)
    return assets
end

function download_asset(asset_url, dir)
    run(`$(wget()) $asset_url -P $dir`)
    filename = replace(basename(asset_url), "%2B" => "+") # TODO: better way to parse URL in unicode?
    return joinpath(dir, filename)
end

if abspath(PROGRAM_FILE) == @__FILE__

    repo_path = abspath(joinpath(@__DIR__, "..", ".."))
    pkg_url = remote_url(repo_path)

    jll_path = joinpath(repo_path, "ray_julia_jll")
    artifacts_toml = joinpath(jll_path, "Artifacts.toml")

    # Read Project.toml
    jll_project_toml = joinpath(jll_path, "Project.toml")
    jll_project = read_project(jll_project_toml)
    jll_version = jll_project.version

    wrappers_dir = joinpath(jll_path, "src", "wrappers")

    artifacts_urls = get_release_asset_urls(jll_version)

    dir = mktempdir()

    for artifact_url in artifacts_urls

        artifact_path = download_asset(artifact_url, dir)

        m = match(TRIPLET_REGEX, basename(artifact_path))
        if isnothing(m)
            throw(ArgumentError("Could not parse host triplet from $(basename(artifact_path))"))
        end

        platform_triplet = m[:triplet]
        julia_version = m[:julia_version]
        platform = parse(BinaryPlatforms.Platform, platform_triplet)

        bind_artifact!(
            artifacts_toml,
            "ray_julia",
            tree_hash_sha1(artifact_path);
            platform=platform,
            download_info=[(artifact_url, sha256sum(artifact_path))],
            force=true
        )

        host_wrapper = joinpath(wrappers_dir, "$platform_triplet-julia_version+$julia_version.jl")
        cp("wrapper.jl.tmp", host_wrapper; force=true)
    end

    @info "Committing and pushing changes to Artifacts.toml for $jll_version"

    message = "Generate artifacts for v$(jll_version)"

    # TODO: ghr and LibGit2 use different credential setups. Double check what BB does here.
    Base.shred!(LibGit2.CredentialPayload()) do credentials
        LibGit2.with(LibGit2.GitRepo(repo_path)) do repo

            # TODO: This allows empty commits
            for file in readdir(wrappers_dir)
                filepath = joinpath("ray_julia_jll", "src", "wrappers", file)
                LibGit2.add!(repo, filepath)
            end
            LibGit2.add!(repo, joinpath("ray_julia_jll", "Artifacts.toml"))
            LibGit2.commit(repo, message)

            # Same as "refs/heads/$branch" but fails if branch doesn't exist locally
            # TODO: Ensure no other files are staged before committing
            # TODO: Ensure no changes between HEAD~main except to Artifacts.toml
            branch = LibGit2.branch(repo)
            branch_ref = LibGit2.lookup_branch(repo, branch)
            refspecs = [LibGit2.name(branch_ref)]

            # TODO: Expecting users to have their branch up to date. Pushing outdated
            # branches will fail like normal git CLI
            LibGit2.push(repo; refspecs, credentials)
        end
    end
end
