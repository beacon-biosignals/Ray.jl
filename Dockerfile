# syntax=docker/dockerfile:1
# Dockerfile is currently only for x86_64

# TODO: Cleanup uid/gid/user work arounds

ARG JULIA_VERSION=1.9.3
ARG RAY_VERSION=2.5.1

FROM julia:${JULIA_VERSION}-bullseye as julia-base

# Based upon `/etc/debian_version` the `ray:2.5.1` image is based on Debian Bullseye.
# No automatic multi-architecture support at the moment. Must specify `-aarch64` suffix
# otherwise the default is x86_64 (https://github.com/ray-project/ray/tree/master/docker/ray#tags)
FROM rayproject/ray:${RAY_VERSION}-py310 as ray-base

# User ID and Group ID for Docker USER
ENV UID=1000
ENV GID=100

# Install Julia
COPY --link --from=julia-base /usr/local/julia /usr/local/julia
ENV JULIA_PATH=/usr/local/julia
ENV PATH=$JULIA_PATH/bin:$PATH

# Validate Julia executable is compatible with the container architecture
RUN if ! julia --history-file=no -e 'exit(0)'; then \
        uname -m && \
        readelf -h ${JULIA_PATH}/bin/julia && \
        exit 1; \
    fi

# Reduces output from `apt-get`
ENV DEBIAN_FRONTEND="noninteractive"

# Set x86_64 targets for improved compatibility
# https://docs.julialang.org/en/v1/devdocs/sysimg/#Specifying-multiple-system-image-targets
ENV JULIA_CPU_TARGET="generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)"

#####
##### deps stage
#####

FROM ray-base as deps

# Disable automatic package precompilation. We'll control when packages are precompiled.
ENV JULIA_PKG_PRECOMPILE_AUTO="0"

# Use the Git CLI when we are not using the Julia's PkgServer as otherwise Docker image
# cross compilation can cause LibGit2 to run out of memory while cloning the General registry.
ENV JULIA_PKG_USE_CLI_GIT="true"

# Switch the Julia depot to use the shared cache storage. As `.ji` files reference
# absolute paths to their included source files care needs to be taken to ensure the depot
# path used during package precompilation matches the final depot path used in the image.
# If a source file no longer resides at the expected location the `.ji` is deemed stale and
# will be recreated.
ARG JULIA_DEPOT_CACHE=/mnt/julia-cache
RUN ln -s ${JULIA_DEPOT_CACHE} ~/.julia

# Install Julia package registries
RUN --mount=type=cache,sharing=locked,target=${JULIA_DEPOT_CACHE},uid=${UID},gid=${GID} \
    mkdir -p ${JULIA_DEPOT_CACHE} && \
    julia -e 'using Pkg; Pkg.Registry.add("General")'

# Instantiate the Julia project environment
ARG RAY_JL_PROJECT=${HOME}/.julia/dev/Ray
COPY --chown=ray *Project.toml *Manifest.toml /tmp/Ray.jl/
RUN --mount=type=cache,sharing=locked,target=${JULIA_DEPOT_CACHE},uid=${UID},gid=${GID} \
    # Move project content into temporary depot
    rm -rf ${RAY_JL_PROJECT} && \
    mv /tmp/Ray.jl ${RAY_JL_PROJECT} && \
    # Generate a fake ray_julia_jll package just for instantiation
    mkdir -p ${RAY_JL_PROJECT}/ray_julia_jll/src && touch ${RAY_JL_PROJECT}/ray_julia_jll/src/ray_julia_jll.jl && \
    # Note: The `timing` flag requires Julia 1.9
    julia --project=${RAY_JL_PROJECT} -e 'using Pkg; Pkg.Registry.update(); Pkg.instantiate(); Pkg.build(); Pkg.precompile(strict=true, timing=true)'

# Copy the shared ephemeral Julia depot into the image and remove any installed packages
# not used by our Manifest.toml.
RUN --mount=type=cache,target=${JULIA_DEPOT_CACHE},uid=${UID},gid=${GID} \
    rm ~/.julia && \
    mkdir ~/.julia && \
    cp -rp ${JULIA_DEPOT_CACHE}/* ~/.julia && \
    julia -e 'using Pkg, Dates; Pkg.gc(collect_delay=Day(0))'

#####
##### ray-jl stage
#####

FROM ray-base as ray-jl

# Install Bazel and compilers
ARG BAZEL_CACHE=/mnt/bazel-cache
RUN set -eux; \
    case $(uname -m) in \
        "x86_64")  ARCH=amd64 ;; \
        "aarch64") ARCH=arm64 ;; \
    esac; \
    sudo apt-get update && \
    sudo apt-get install -qq build-essential curl gcc-9 g++-9 pkg-config psmisc unzip && \
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 \
        --slave /usr/bin/g++ g++ /usr/bin/g++-9 \
        --slave /usr/bin/gcov gcov /usr/bin/gcov-9 && \
    curl -sSLo bazel https://github.com/bazelbuild/bazelisk/releases/download/v1.18.0/bazelisk-linux-${ARCH} && \
    sudo install bazel /usr/local/bin && \
    ln -s ${BAZEL_CACHE} ~/.cache/bazel

# Install npm
# https://docs.ray.io/en/releases-2.5.1/ray-contribute/development.html#preparing-to-build-ray-on-linux
COPY --from=node:14-bullseye /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node:14-bullseye /usr/local/bin/node /usr/local/bin/
RUN sudo ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
RUN node --version && \
    npm --version

ARG RAY_JL_PROJECT=${HOME}/.julia/dev/Ray
ARG RAY_JLL_PROJECT=${RAY_JL_PROJECT}/ray_julia_jll

# Install custom Ray CLI which supports the Julia language.
# https://docs.ray.io/en/releases-2.5.1/ray-contribute/development.html#building-ray-on-linux-macos-full
ARG RAY_REPO=${HOME}/ray
ARG RAY_COMMIT=448a83caf4
ARG RAY_REPO_CACHE=/mnt/ray-cache
ARG RAY_CACHE_CLEAR=false
RUN --mount=type=cache,sharing=locked,target=${BAZEL_CACHE},uid=${UID},gid=${GID} \
    --mount=type=cache,sharing=locked,target=${RAY_REPO_CACHE},uid=${UID},gid=${GID} \
    set -eux && \
    git clone https://github.com/beacon-biosignals/ray ${RAY_REPO} && \
    git -C ${RAY_REPO} checkout ${RAY_COMMIT} && \
    #
    # Build using the final Ray.jl destination
    mkdir -p ${RAY_JLL_PROJECT}/deps && \
    ln -s ${RAY_REPO} ${RAY_JLL_PROJECT}/deps/ray && \
    cd ${RAY_JLL_PROJECT}/deps/ray && \
    #
    # Allow builders to clear just the Ray CLI cache.
    if [ "${RAY_CACHE_CLEAR}" != "false" ]; then \
        bazel clean --expunge && \
        rm -rf ${RAY_REPO_CACHE}/*; \
    fi && \
    #
    # The Ray `BUILD.bazel` includes a bunch of `copy_to_workspace` rules which copy build output
    # into the Ray worktree. When we only restore the Bazel cache then re-building causes these
    # rules to be skipped resulting in `error: [Errno 2] No such file or directory`. By manually
    # saving/restoring these files we can work around this.
    if [ -d ${RAY_REPO_CACHE}/.git ]; then \
        cd ${RAY_REPO_CACHE} && \
        cp -rp --parents \
            python/ray/_raylet.so \
            python/ray/core/generated \
            python/ray/serve/generated \
            python/ray/core/src/ray/raylet/raylet \
            python/ray/core/src/ray/gcs \
            ${RAY_REPO} && \
        cd -; \
    fi && \
    #
    # Build the dashboard
    cd ${RAY_JLL_PROJECT}/deps/ray/python/ray/dashboard/client && \
    npm ci && \
    npm run build && \
    #
    # Build Ray for Python
    cd ${RAY_JLL_PROJECT}/deps/ray/python && \
    pip install --verbose . && \
    #
    # By copying the entire Ray worktree we can easily restore missing files without having to
    # delete the cache and build from scratch.
    mkdir -p ${RAY_REPO_CACHE} && \
    cp -rfp ${RAY_REPO}/. ${RAY_REPO_CACHE}

# Copy over artifacts generated during the previous stages
COPY --chown=ray --link --from=deps ${HOME}/.julia ${HOME}/.julia

# Setup ray_julia_jll
ARG RAY_JLL_REPO=${HOME}/.julia/dev/ray_julia_jll
COPY --chown=ray ray_julia_jll ${RAY_JLL_REPO}
RUN --mount=type=cache,sharing=locked,target=${BAZEL_CACHE},uid=${UID},gid=${GID} \
    set -eux && \
    #
    # Build using the final Ray.jl destination
    ln -s ${RAY_REPO} ${RAY_JLL_REPO}/deps/ray && \
    rm -rf ${RAY_JLL_PROJECT} && \
    ln -s ${RAY_JLL_REPO} ${RAY_JLL_PROJECT} && \
    #
    # Build ray_julia_jll
    julia --project=${RAY_JLL_PROJECT} -e 'using Pkg; Pkg.build(verbose=true); Pkg.precompile(strict=true)' && \
    #
    # Cleanup build data
    cp -rpL ${RAY_JLL_PROJECT}/deps/bazel-bin ${RAY_JLL_PROJECT}/deps/bin && \
    rm ${RAY_JLL_PROJECT}/deps/bazel-* && \
    rm ${RAY_JLL_PROJECT}

# Overwrite the Overrides.toml created during Pkg.build
COPY --chown=ray <<-EOF ${HOME}/.julia/artifacts/Overrides.toml
[c348cde4-7f22-4730-83d8-6959fb7a17ba]
ray_julia = "${RAY_JL_PROJECT}/ray_julia_jll/deps/bin"
EOF

COPY --chown=ray . ${RAY_JL_PROJECT}/

# Restore content from previously built ray_julia_jll directory
RUN rm -rf ${RAY_JLL_PROJECT} && \
    ln -s ${RAY_JLL_REPO} ${RAY_JLL_PROJECT}

# Note: The `timing` flag requires Julia 1.9
RUN julia -e 'using Pkg; Pkg.precompile(strict=true, timing=true); using Ray'

# Set up default project and working dir so that users need only pass in the requisite script input args
WORKDIR ${RAY_JL_PROJECT}

