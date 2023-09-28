using Base: BinaryPlatforms
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

    host_triplet = BinaryPlatforms.host_triplet()
    tarball_name = "ray_julia.$TAG.$host_triplet.tar.gz"

    @info "Creating tarball $tarball_name"
    compiled_dir = joinpath(REPO_PATH, "build", "bazel-bin")
    tarball_path = joinpath(TARBALL_DIR, tarball_name)
    create_tarball(readlink(compiled_dir), tarball_path)
end
