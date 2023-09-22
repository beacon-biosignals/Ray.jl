using Base: SHA1, BinaryPlatforms
using CodecZlib: GzipCompressorStream
using CURL_jll
using jq_jll
using Pkg.Artifacts: bind_artifact!
using SHA: sha256
using Tar
using wget_jll

const DIR = mktempdir()
const GITHUB_URL = "https://api.github.com/repos"

include("common.jl")

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

function get_release_asset_urls()
    # e.g. "git@github.com:beacon-biosignals/ray.jl"
    _, pkg = split(PKG_URL, ":")
    assets_url = joinpath(GITHUB_URL, "$pkg", "releases", "tags", "$TAG")
    io = IOBuffer()
    run(pipeline(`$(curl()) $assets_url`, `$(jq()) -r '.assets[].browser_download_url'`, io))
    assets = split(String(take!(io)), "\n"; keepempty=false)
    return assets
end

function download_asset(asset_url)
    run(`$(wget()) $asset_url -P $DIR`)
    filename = replace(basename(asset_url), "%2B" => "+") # TODO: better way to parse URL in unicode?
    return joinpath(DIR, filename)
end

if abspath(PROGRAM_FILE) == @__FILE__

    artifacts_urls = get_release_asset_urls()

    for artifact_url in artifacts_urls

        artifact_path = download_asset(artifact_url)

        m = match(TARBALL_REGEX, basename(artifact_path))
        if isnothing(m)
            throw(ArgumentError("Could not parse host triplet from $(basename(artifact_path))"))
        end

        platform_triplet = m[:triplet]
        julia_version = m[:julia_version]
        platform = parse(BinaryPlatforms.Platform, platform_triplet)

        bind_artifact!(
            JLL_ARTIFACTS_TOML,
            "ray_julia",
            tree_hash_sha1(artifact_path);
            platform=platform,
            download_info=[(artifact_url, sha256sum(artifact_path))],
            force=true
        )

        host_wrapper = joinpath(WRAPPERS_DIR, "$platform_triplet-julia_version+$julia_version.jl")
        cp("wrapper.jl.tmp", host_wrapper; force=true)
    end
end
