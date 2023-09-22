using Base: BinaryPlatforms
using CodecZlib: GzipCompressorStream
using LibGit2: LibGit2
using Pkg
using Pkg.Types: read_project
using Tar: Tar

const TARBALL_DIR = joinpath(@__DIR__, "tarballs")
const SO_FILE = "julia_core_worker_lib.so"

function create_tarball(dir, tarball)
    return mktempdir() do tmpdir
        cp(joinpath(dir, SO_FILE), joinpath(tmpdir, SO_FILE))
        return open(GzipCompressorStream, tarball, "w") do tar
            Tar.create(tmpdir, tar)
        end
    end
end

function remote_url(repo_root::AbstractString, name::AbstractString="origin")
    return LibGit2.with(LibGit2.GitRepo(repo_root)) do repo
        LibGit2.with(LibGit2.lookup_remote(repo, name)) do remote
            LibGit2.url(remote)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__

    isdir(TARBALL_DIR) || mkdir(TARBALL_DIR)

    repo_path = abspath(joinpath(@__DIR__, "..", ".."))
    pkg_url = remote_url(repo_path)

    # Build JLL
    @info "Building ray_julia_jll..."
    Pkg.build("ray_julia_jll"; verbose=true)

    # Read Project.toml
    jll_project_toml = joinpath(repo_path, "ray_julia_jll", "Project.toml")
    jll_project = read_project(jll_project_toml)
    jll_version = jll_project.version

    host_triplet = BinaryPlatforms.host_triplet()
    tarball_name = "ray_julia.v$jll_version.$host_triplet.tar.gz"

    @info "Creating tarball $tarball_name"
    compiled_dir = joinpath(repo_path, "ray_julia_jll", "deps", "bazel-bin")
    tarball_path = joinpath(TARBALL_DIR, tarball_name)
    create_tarball(readlink(compiled_dir), tarball_path)
end
