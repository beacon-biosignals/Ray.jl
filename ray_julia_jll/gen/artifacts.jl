#===
1. Publish GitHub release (still a pre-release).
   This will make the assets accessible from consistent URLs.

2. Commit changes to Artifacts and wrappers
   CI workflows for this PR can run successfully and the referenced artifacts will be accessible.
===#

using Base: SHA1
using LibGit2: LibGit2
using Pkg.Artifacts: bind_artifact!
using Pkg.Types: read_project
using SHA: sha256

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

function get_release_artifacts(pkg_url, version)
    # TODO
end

if abspath(PROGRAM_FILE) == @__FILE__

    repo_path = abspath(joinpath(@__DIR__, "..", ".."))
    artifacts_toml = joinpath(repo_path, "ray_julia_jll", "Artifacts.toml")
    pkg_url = remote_url(repo_path)

    # Read Project.toml
    jll_project_toml = joinpath(repo_path, "ray_julia_jll", "Project.toml")
    jll_project = read_project(jll_project_toml)
    jll_version = jll_project.version

    wrappers_dir = joinpath(repo_path, "ray_julia_jll", "src", "wrappers")

    artifacts = get_release_artifacts(pkg_url, jll_version)

    # TODO: Ensure no other files are staged before committing
    # TODO: Ensure no changes between HEAD~main except to Artifacts.toml
    branch = LibGit2.with(LibGit2.branch, LibGit2.GitRepo(repo_path))

    for artifact in artifacts

        tarball_path = ""
        host_triplet = ""

        bind_artifact!(
            artifacts_toml,
            "ray_julia",
            tree_hash_sha1(tarball_path);
            platform=artifact.host,
            download_info=[(artifact_url, sha256sum(tarball_path))]
        )

        host_wrapper = joinpath(wrappers_dir, "$host_triplet.jl")
        cp("wrapper.jl.tmp", host_wrapper; force=true)
    end


    @info "Committing and pushing changes to Artifacts.toml for $jll_version"

    message = "Generate artifacts for v$(jll_version)"

    # TODO: ghr and LibGit2 use different credential setups. Double check what BB does here.
    Base.shred!(LibGit2.CredentialPayload()) do credentials
        LibGit2.with(LibGit2.GitRepo(repo_path)) do repo

            # TODO: This allows empty commits
            LibGit2.add!(artifacts_toml)
            LibGit2.add!(wrappers_dir)
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
