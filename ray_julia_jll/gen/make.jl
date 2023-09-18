using Base: SHA1, BinaryPlatforms
using CodecZlib: GzipCompressorStream, GzipDecompressorStream
using LibGit2: LibGit2
using Pkg
using Pkg.Artifacts: bind_artifact!
using Pkg.Types: read_project
using SHA: sha256
using Tar: Tar
using TOML: TOML

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

if abspath(PROGRAM_FILE) == @__FILE__

    # e.g. ray_julia.v0.1.0.aarch64-apple-darwin-libgfortran5-cxx11-julia_version+1.9.2
    host = BinaryPlatforms.HostPlatform()
    repo_path = abspath(joinpath(@__DIR__, "..", ".."))

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

    host_wrapper = joinpath(repo_path, "ray_julia_jll", "src", "wrappers", "$host_triplet.jl")
    cp("wrapper.jl.tmp", host_wrapper; force=true)

    # TODO: Ensure no other files are staged before committing
    # TODO: Ensure no changes between HEAD~main except to Artifacts.toml
    branch = LibGit2.with(LibGit2.branch, LibGit2.GitRepo(repo_path))
    @info "Committing and pushing changes to Artifacts.toml on $branch"

    message = "Generate artifact for v$(jll_version) on $host_triplet"

    # TODO: ghr and LibGit2 use different credential setups. Double check what BB does here.
    Base.shred!(LibGit2.CredentialPayload()) do credentials
        LibGit2.with(LibGit2.GitRepo(repo_path)) do repo

            # TODO: This allows empty commits
            LibGit2.add!(artifacts_toml)
            LibGit2.add!(host_wrapper)
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
