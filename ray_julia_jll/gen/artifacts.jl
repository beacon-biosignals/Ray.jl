using Base: SHA1, BinaryPlatforms
using CodecZlib: GzipDecompressorStream
using Downloads
using JSON3
using Pkg.Artifacts: bind_artifact!
using SHA: sha256
using Tar
using URIs: unescapeuri

const DIR = mktempdir()

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
    io = IOBuffer()
    Downloads.download(ASSETS_URL, io)
    json = JSON3.read(String(take!(io)))
    return unescapeuri.(get.(json[:assets], :browser_download_url))
end

if abspath(PROGRAM_FILE) == @__FILE__

    @info "Fetching assets for $TAG"
    artifacts_urls = get_release_asset_urls()

    for artifact_url in artifacts_urls

        @info "Adding artifact for $(basename(artifact_url))"
        artifact_path = Downloads.download(artifact_url, joinpath(DIR, basename(artifact_url)))

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
