using CxxWrap
using Mustache
using TOML

const BUILD_DIR = @__DIR__()
const PROJECT_TOML = joinpath(BUILD_DIR, "..", "Project.toml")
const ARTIFACT_DIR = joinpath(BUILD_DIR, "bazel-bin")
const RAY_DIR = joinpath(BUILD_DIR, "ray")
const RAY_COMMIT = readchomp(joinpath(BUILD_DIR, "ray_commit"))
const LIBRARY_NAME = "julia_core_worker_lib.so"

const TEMPLATE_DICT = Dict("JULIA_INCLUDE_DIR" => joinpath(Sys.BINDIR, "..", "include"),
                           "CXXWRAP_PREFIX_DIR" => CxxWrap.prefix_path(),
                           "RAY_DIR" => RAY_DIR)

function build_library(; override::Bool=true)
    template = Mustache.load(joinpath(BUILD_DIR, "WORKSPACE.bazel.tpl"))

    open(joinpath(BUILD_DIR, "WORKSPACE.bazel"), "w+") do io
        Mustache.render(io, template, TEMPLATE_DICT)
        return nothing
    end

    #! format: off
    # Clone "ray" repo when the directory is missing or empty
    isdir(RAY_DIR) && !isempty(readdir(RAY_DIR)) || cd(dirname(RAY_DIR)) do
        run(`git clone https://github.com/beacon-biosignals/ray $(basename(RAY_DIR))`)
        return nothing
    end
    #! format: on

    # Ensure that library is always built against the same version of ray
    if !("--no-checkout" in ARGS)
        run(`git -C $RAY_DIR fetch origin`)
        run(`git -C $RAY_DIR checkout $RAY_COMMIT`)
    end

    cd(BUILD_DIR) do
        run(`bazel build $LIBRARY_NAME`)
        return nothing
    end

    if !isfile(joinpath(ARTIFACT_DIR, LIBRARY_NAME))
        error("Failed to build library: $(joinpath(ARTIFACT_DIR, LIBRARY_NAME))")
    end

    # Add entry to depot Overrides.toml
    if override
        pkg_uuid = TOML.parsefile(PROJECT_TOML)["uuid"]

        overrides_toml = joinpath(first(DEPOT_PATH), "artifacts", "Overrides.toml")
        overrides_dict = isfile(overrides_toml) ? TOML.parsefile(overrides_toml) :
                         Dict{String,Any}()
        overrides_dict[pkg_uuid] = Dict("ray_julia" => abspath(ARTIFACT_DIR))
        open(overrides_toml, "w") do io
            TOML.print(io, overrides_dict)
            return nothing
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    override = !("--no-override" in ARGS)
    build_library(; override)
end
