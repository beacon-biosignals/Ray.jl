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


function build_host_tarball()
    isdir(TARBALL_DIR) || mkdir(TARBALL_DIR)

    @info "Building ray_julia library..."
    include("build_library.jl")

    @info "Creating tarball $tarball_name"
    compiled_dir = readlink(joinpath(REPO_PATH, "build", "bazel-bin"))
    create_tarball(compiled_dir, TARBALL_PATH)
end
