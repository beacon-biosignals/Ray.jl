using LibGit2: LibGit2
using Pkg.Types: read_project

const TARBALL_DIR = joinpath(@__DIR__, "tarballs")
const SO_FILE = "julia_core_worker_lib.so"

function remote_url(repo_root::AbstractString, name::AbstractString="origin")
    return LibGit2.with(LibGit2.GitRepo(repo_root)) do repo
        LibGit2.with(LibGit2.lookup_remote(repo, name)) do remote
            LibGit2.url(remote)
        end
    end
end

const REPO_PATH = abspath(joinpath(@__DIR__, "..", ".."))
const PKG_URL = remote_url(REPO_PATH)

# Read Project.toml
const JLL_PROJECT_TOML = joinpath(REPO_PATH, "ray_julia_jll", "Project.toml")
const JLL_PROJECT = read_project(JLL_PROJECT_TOML)
const TAG = "v$(JLL_PROJECT.version)"
