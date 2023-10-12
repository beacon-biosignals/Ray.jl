using Downloads: Downloads
using JSON3: JSON3
using ZipFile: ZipFile

include("common.jl")

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

function download_ray_julia_artifacts(; commit_sha, token, tarball_dir=TARBALL_DIR)
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

        if length(zip.files) > 1
            error("GitHub workflow artifact contains more than one file:\n$(join(zip.files, '\n'))")
        end

        file = only(zip.files)
        write(joinpath(tarball_dir, name), read(file))
    end

    return nothing
end

function download_tarballs()
    token = github_token()

    commit_sha = git_head_sha()
    @info "Retrieving CI built tarballs for $commit_sha..."
    download_ray_julia_artifacts(; commit_sha, token)

    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    download_tarballs()
end
