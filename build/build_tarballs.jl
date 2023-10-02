using CodecZlib: GzipCompressorStream
using Downloads: Downloads
using JSON3: JSON3
using Pkg
using Tar: Tar
using ZipFile: ZipFile

include("common.jl")
include("build_library.jl")

function create_tarball(dir, tarball)
    return mktempdir() do tmpdir
        cp(joinpath(dir, SO_FILE), joinpath(tmpdir, SO_FILE))
        return open(GzipCompressorStream, tarball, "w") do tar
            return Tar.create(tmpdir, tar)
        end
    end
end

# https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28#list-workflow-runs-for-a-repository
function list_workflow_runs(; org, repo, head_sha)
    # Needs to be a full SHA
    url = "https://api.github.com/repos/$org/$repo/actions/runs?head_sha=$head_sha"
    b = Downloads.download(url, IOBuffer())
    return JSON3.read(seekstart(b))
end

# https://docs.github.com/en/rest/actions/artifacts?apiVersion=2022-11-28#list-workflow-run-artifacts
function list_workflow_run_artifacts(; org, repo, run_id)
    url = "https://api.github.com/repos/$org/$repo/actions/runs/$run_id/artifacts"
    b = Downloads.download(url, IOBuffer())
    return JSON3.read(seekstart(b))
end

function download_ray_julia_artifacts(; commit_sha, token, tarball_dir)
    isdir(tarball_dir) || mkpath(tarball_dir)

    response = list_workflow_runs(; org=REPO_ORG, repo=REPO_NAME, head_sha=commit_sha)
    run_id = only(filter(r -> r.name == ARTIFACTS_WORKFLOW_NAME, response.workflow_runs)).id

    response = list_workflow_run_artifacts(; org=REPO_ORG, repo=REPO_NAME, run_id)
    artifacts = map(j -> j.name => j.archive_download_url, response.artifacts)

    headers = ["Authorization" => "Bearer $token"]
    for (name, url) in artifacts
        startswith(name, "ray_julia") || continue

        @info "Downloading $name"
        io = Downloads.download(url, IOBuffer(); headers)
        zip = ZipFile.Reader(io)

        length(zip.files) == 1 || error("GitHub workflow artifact contains more than one file:\n$(join(zip.files, '\n'))")

        file = only(zip.files)
        write(joinpath(tarball_dir, name), read(file))
    end

    return nothing
end

function build_host_tarball(; tarball_dir, override::Bool=true)
    isdir(tarball_dir) || mkdir(tarball_dir)

    @info "Building ray_julia library..."
    build_library(; override)

    host = supported_platform(HostPlatform())
    tarball_name = gen_artifact_filename(; tag=TAG, platform=host)

    @info "Creating tarball $tarball_name"
    tarball_path = joinpath(tarball_dir, tarball_name)
    create_tarball(COMPILED_DIR, tarball_path)

    return tarball_path
end

function main()
    if "--all" in ARGS
        # Note: Using `--all` purposefully ignores the `--no-override` setting
        for v in REQUIRED_JULIA_VERSIONS
            julia = "julia-$(v.major).$(v.minor)"
            code = "include(\"$(@__FILE__())\"); build_host_tarball(override=false)"
            run(`$julia --project=$(Pkg.project().path) -e $code`)
        end
    elseif "--fetch" in ARGS
        token = get(ENV, "GITHUB_TOKEN") do
            Base.shred!(Base.getpass("GitHub PAT")) do s
                read(s, String)
            end
        end

        @info "Retrieving CI built tarballs..."
        commit_sha = git_head_sha()
        download_ray_julia_artifacts(; commit_sha, token, tarball_dir=TARBALL_DIR)
    else
        override = !("--no-override" in ARGS)
        build_host_tarball(; override, tarball_dir=TARBALL_DIR)
    end

    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
