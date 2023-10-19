using Base: SHA1, BinaryPlatforms
using CodecZlib: GzipDecompressorStream
using Downloads
using JSON3
using Pkg.Artifacts: bind_artifact!
using SHA: sha256
using Tar
using URIs: unescapeuri

include("common.jl")

# Compute the Artifact.toml `git-tree-sha1`.
function tree_hash_sha1(tarball_path)
    return open(GzipDecompressorStream, tarball_path, "r") do tar
        return SHA1(Tar.tree_hash(tar))
    end
end

# Compute the Artifact.toml `sha256` from the compressed archive.
function sha256sum(tarball_path)
    return open(tarball_path, "r") do tar
        return bytes2hex(sha256(tar))
    end
end

function bind_artifacts()
    # Start with a clean Artifacts.toml so that unsupported platforms are removed
    isfile(ARTIFACTS_TOML) && rm(ARTIFACTS_TOML)

    for platform in REQUIRED_PLATFORMS
        artifact_name = gen_artifact_filename(; tag=TAG, platform)
        artifact_url = gen_artifact_url(; repo_url=REPO_HTTPS_URL, tag=TAG,
                                        filename=artifact_name)

        artifact_path = joinpath(TARBALL_DIR, artifact_name)
        isfile(artifact_path) || error("No such file $artifact_path")

        @info "Adding artifact for $(triplet(platform))"
        bind_artifact!(ARTIFACTS_TOML,
                       "ray_julia",
                       tree_hash_sha1(artifact_path);
                       platform=platform,
                       download_info=[(artifact_url, sha256sum(artifact_path))])
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    bind_artifacts()
end
