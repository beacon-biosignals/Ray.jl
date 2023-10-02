using Base.BinaryPlatforms
using LibGit2: LibGit2
using Pkg.Types: read_project
using URIs: URI

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
    (?<tag>[^/]+)/?$
    """x

const REQUIRED_BASE_TRIPLETS = ("x86_64-linux-gnu", "aarch64-apple-darwin")
const REQUIRED_JULIA_VERSIONS = (v"1.8", v"1.9")
const REQUIRED_PLATFORMS = let
    base_platforms = parse.(Platform, REQUIRED_BASE_TRIPLETS)
    base_tags = [(; julia_version=string(v)) for v in REQUIRED_JULIA_VERSIONS]
    [Platform(arch(p), platform_name(p); tags...)
     for p in base_platforms, tags in base_tags][:]
end

function remote_url(repo_root::AbstractString, name::AbstractString="origin")
    return LibGit2.with(LibGit2.GitRepo(repo_root)) do repo
        LibGit2.with(LibGit2.lookup_remote(repo, name)) do remote
            return LibGit2.url(remote)
        end
    end
end

function git_head_sha(repo_root::AbstractString=REPO_PATH)
    return LibGit2.with(LibGit2.GitRepo(repo_root)) do repo
        ref = LibGit2.head(repo)
        commit = LibGit2.peel(LibGit2.GitCommit, ref)
        return string(LibGit2.GitHash(commit))
    end
end

function convert_to_https_url(url)
    m = match(LibGit2.URL_REGEX, url)
    if m === nothing
        throw(ArgumentError("URL is not a valid SCP or HTTP(S) URL: $(url)"))
    end
    # Purposefully excluding username as we're assuming this is a public repo
    return LibGit2.git_url(; scheme="https", host=something(m[:host], ""),
                           port=something(m[:port], ""), path=something(m[:path], ""))
end

# Used to convert `HostPlatform` into something contained in
# `BinaryBuilder.support_platforms()`
function supported_platform(p::Platform)
    support_tags = filter((k, v)::Pair -> k in ("call_abi", "libc"), tags(p))
    support_tags["julia_version"] = string(Base.thisminor(VERSION))
    support_tags = [Symbol(k) => v for (k, v) in support_tags]
    return Platform(arch(p), platform_name(p); support_tags...)
end

function gen_artifact_url(; repo_url, tag, filename)
    return join([repo_url, "releases", "download", tag, filename], '/')
end

function gen_artifact_filename(; tag::AbstractString, platform::Platform)
    return "ray_julia.$tag.$(triplet(platform)).tar.gz"
end

const REPO_PATH = abspath(joinpath(@__DIR__, ".."))
const REPO_HTTPS_URL = convert_to_https_url(remote_url(REPO_PATH))
const REPO_ORG = split(parse(URI, REPO_HTTPS_URL).path, '/')[2]
const REPO_NAME = split(parse(URI, REPO_HTTPS_URL).path, '/')[3]
const COMPILED_DIR = joinpath(REPO_PATH, "build", "bazel-bin")

const ARTIFACTS_TOML = joinpath(REPO_PATH, "Artifacts.toml")
const ARTIFACTS_WORKFLOW_NAME = "CI"

const TAG = let
    project_toml = joinpath(REPO_PATH, "Project.toml")
    project = read_project(project_toml)
    "v$(project.version)"
end
