using Base.BinaryPlatforms
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
            return LibGit2.url(remote)
        end
    end
end

# Used to convert `HostPlatform` into something contained in
# `BinaryBuilder.support_platforms()`
function supported_platform(p::Platform)
    support_tags = filter((k, v)::Pair -> k in ("call_abi", "libc"), tags(p))
    support_tags = [Symbol(k) => v for (k, v) in support_tags]
    return Platform(arch(p), platform_name(p); support_tags...)
end

const REPO_PATH = abspath(joinpath(@__DIR__, ".."))
const PKG_URL = remote_url(REPO_PATH)

# Read Project.toml
const PROJECT_TOML = joinpath(REPO_PATH, "Project.toml")
const ARTIFACTS_TOML = joinpath(REPO_PATH, "Artifacts.toml")

const PROJECT = read_project(PROJECT_TOML)
const TAG = "v$(PROJECT.version)"

const GITHUB_URL = "https://api.github.com/repos"
const _PKG = split(PKG_URL, ":")[2]
const ASSETS_URL = joinpath(GITHUB_URL, "$_PKG", "releases", "tags", "$TAG")
