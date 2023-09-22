using LibGit2: LibGit2
using Pkg.Types: read_project

const TARBALL_DIR = joinpath(@__DIR__, "tarballs")
const SO_FILE = "julia_core_worker_lib.so"

const TARBALL_REGEX = r"""
    ^ray_julia\.v(?<jll_version>[0-9]+(\.[0-9]+){2})\.
    (?<triplet>[a-z0-9_-]+)-
    julia_version\+(?<julia_version>[0-9]+(\.[0-9]+){2})\.
    tar\.gz$
    """x

const GH_RELEASE_ASSET_PATH_REGEX = r"""
    ^/(?<owner>[^/]+)/(?<repo_name>[^/]+)/
    releases/download/
    (?<tag>[^/]+)$
    """x

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
const JLL_ARTIFACTS_TOML = joinpath(REPO_PATH, "ray_julia_jll", "Artifacts.toml")
const WRAPPERS_DIR = joinpath(REPO_PATH, "ray_julia_jll", "src", "wrappers")

const JLL_PROJECT = read_project(JLL_PROJECT_TOML)
const TAG = "v$(JLL_PROJECT.version)"

const GITHUB_URL = "https://api.github.com/repos"
const _PKG = split(PKG_URL, ":")[2]
const ASSETS_URL = joinpath(GITHUB_URL, "$_PKG", "releases", "tags", "$TAG")
