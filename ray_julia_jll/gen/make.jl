using AWSS3: get_config, s3_put, S3Path
using Base: SHA1, BinaryPlatforms
using CodecZlib: GzipCompressorStream, GzipDecompressorStream
using LibGit2: LibGit2
using Pkg
using Pkg.Artifacts: bind_artifact!
using Pkg.Types: read_project
using SHA: sha256
using Tar: Tar
using TOML: TOML

# TODO: change to public bucket
const ARTIFACTS_PATH = "TODO"

const ASSETS = Set(["external",
                    "julia_core_worker_lib.so-2.params",
                    "_objs",
                    "julia_core_worker_lib.so.runfiles_manifest",
                    "julia_core_worker_lib.so",
                    "julia_core_worker_lib.so.runfiles"])

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

function upload_to_s3(tarball)
    fp = joinpath(ARTIFACTS_PATH, basename(tarball))
    s3_put(get_config(fp), fp.bucket, fp.key, read(tarball))
    return fp
end

if abspath(PROGRAM_FILE) == @__FILE__

    repo_path = abspath(joinpath(@__DIR__, "..", ".."))

    # Read Project.toml
    jll_project_toml = joinpath(repo_path, "ray_julia_jll", "Project.toml")
    jll_project = read_project(jll_project_toml)
    jll_version = jll_project.version

    # e.g. ray_julia.v0.1.0.aarch64-apple-darwin-libgfortran5-cxx11-julia_version+1.9.2
    host = BinaryPlatforms.host_triplet()
    tarball_name = "ray_julia.v$jll_version.$host.tar.gz"

    # Build JLL
    # TODO: execute inside a python venv
    @info "Building ray_julia_jll on $host"
    Pkg.build("ray_julia_jll"; verbose=true)
    compiled_dir = joinpath(repo_path, "ray_julia_jll", "deps", "bazel-bin")

    # Limit what we include in tarball
    compiled_assets = Set(readdir(compiled_dir))
    if compiled_assets != ASSETS
        throw(ArgumentError("Unexpected JLL assets found: $compiled_assets"))
    end

    @info "Creating tarball $tarball_name"
    tarball_path = joinpath(tempdir(), tarball_name)
    create_tarball(readlink(compiled_dir), tarball_path)

    @info "Uploading to $ARTIFACTS_PATH"
    # TODO: have a rollback in case the changes below fail
    artifact_url = upload_to_s3(tarball_path)

    # https://github.com/JuliaLang/Pkg.jl/issues/3623
    host = Base.BinaryPlatforms.HostPlatform()
    delete!(host.compare_strategies, "libstdcxx_version")

    artifacts_toml = joinpath(repo_path, "ray_julia_jll", "Artifacts.toml")
    bind_artifact!(
        artifacts_toml,
        "ray_julia",
        tree_hash_sha1(tarball_path);
        platform=host,
        download_info=[(artifact_url, sha256sum(tarball_path))],
    )

    # TODO: Ensure no other files are staged before committing
    branch = LibGit2.with(LibGit2.branch, LibGit2.GitRepo(repo_path))
    @info "Committing and pushing changes to Artifacts.toml on $branch"

    message = "Generate artifact for v$(jll_version) on $(os(host))-$(arch(host))-julia-v$VERSION"

    # TODO: ghr and LibGit2 use different credential setups. Double check what BB does here.
    Base.shred!(LibGit2.CredentialPayload()) do credentials
        LibGit2.with(LibGit2.GitRepo(repo_path)) do repo

            # TODO: This allows empty commits
            LibGit2.add!(repo, joinpath("ray_julia_jll", basename(artifacts_toml)))
            LibGit2.commit(repo, message)

            # Same as "refs/heads/$branch" but fails if branch doesn't exist locally
            branch_ref = LibGit2.lookup_branch(repo, branch)
            refspecs = [LibGit2.name(branch_ref)]

            # TODO: Expecting users to have their branch up to date. Pushing outdated
            # branches will fail like normal git CLI
            LibGit2.push(repo; refspecs, credentials)
        end
    end
end
