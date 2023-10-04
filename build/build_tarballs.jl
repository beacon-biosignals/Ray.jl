using CodecZlib: GzipCompressorStream
using Tar: Tar

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

function build_host_tarball(; tarball_dir=TARBALL_DIR, override::Bool=true)
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

if abspath(PROGRAM_FILE) == @__FILE__
    override = !("--no-override" in ARGS)
    build_host_tarball(; override)
end
