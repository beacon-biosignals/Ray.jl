using CodecZlib: GzipCompressorStream
using Pkg
using Tar: Tar

include("common.jl")

function create_tarball(dir, tarball)
    return mktempdir() do tmpdir
        cp(joinpath(dir, SO_FILE), joinpath(tmpdir, SO_FILE))
        return open(GzipCompressorStream, tarball, "w") do tar
            return Tar.create(tmpdir, tar)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    isdir(TARBALL_DIR) || mkdir(TARBALL_DIR)

    @info "Building ray_julia library..."
    include("build_library.jl")

    host = supported_platform(HostPlatform())
    tarball_name = gen_artifact_filename(; tag=TAG, platform=host)

    @info "Creating tarball $tarball_name"
    tarball_path = joinpath(TARBALL_DIR, tarball_name)
    create_tarball(COMPILED_DIR, tarball_path)
end
