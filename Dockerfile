# syntax=docker/dockerfile:1

# TODO: Cleanup uid/gid/user work arounds

ARG JULIA_VERSION=1.9.3
ARG RAY_VERSION=2.5.1

FROM julia:${JULIA_VERSION}-bullseye as julia-base

# Based upon `/etc/debian_version` the `ray:2.5.1` image is based on Debian Bullseye.
# No automatic multi-architecture support at the moment. Must specify `-aarch64` suffix
# otherwise the default is x86_64 (https://github.com/ray-project/ray/tree/master/docker/ray#tags)
FROM rayproject/ray:${RAY_VERSION}-py310 as ray-base

# Install Julia
COPY --link --from=julia-base /usr/local/julia /usr/local/julia
ENV JULIA_PATH /usr/local/julia
ENV PATH $JULIA_PATH/bin:$PATH

# Validate Julia executable is compatible with the container architecture
RUN if ! julia --history-file=no -e 'exit(0)'; then \
        uname -m && \
        readelf -h ${JULIA_PATH}/bin/julia && \
        exit 1; \
    fi

# Reduces output from `apt-get`
ENV DEBIAN_FRONTEND="noninteractive"

#####
##### deps stage
#####

FROM ray-base as deps

# Disable automatic package precompilation. We'll control when packages are precompiled.
ENV JULIA_PKG_PRECOMPILE_AUTO "0"

# Use the Git CLI when we are not using the Julia's PkgServer as otherwise Docker image
# cross compilation can cause LibGit2 to run out of memory while cloning the General registry.
ENV JULIA_PKG_USE_CLI_GIT="true"

# Switch the Julia depot to use the shared cache storage. As `.ji` files reference
# absolute paths to their included source files care needs to be taken to ensure the depot
# path used during package precompilation matches the final depot path used in the image.
# If a source file no longer resides at the expected location the `.ji` is deemed stale and
# will be recreated.
RUN ln -s /tmp/julia-cache ~/.julia

# Install Julia package registries
RUN --mount=type=cache,sharing=locked,target=/tmp/julia-cache,uid=1000,gid=100 \
    mkdir -p /tmp/julia-cache && \
    julia -e 'using Pkg; Pkg.Registry.add("General")'

# Instantiate the Julia project environment
ENV JULIA_PROJECT /Ray.jl
COPY --chown=ray *Project.toml *Manifest.toml ${JULIA_PROJECT}/

# Generate a fake ray_julia_jll package just for instantiation
RUN mkdir -p ${JULIA_PROJECT}/ray_julia_jll/src && touch ${JULIA_PROJECT}/ray_julia_jll/src/ray_julia_jll.jl

# Note: The `timing` flag requires Julia 1.9
RUN --mount=type=cache,sharing=locked,target=/tmp/julia-cache,uid=1000,gid=100 \
    julia -e 'using Pkg; Pkg.Registry.update(); Pkg.instantiate(); Pkg.build(); Pkg.precompile(strict=true, timing=true)'

# Copy the shared ephemeral Julia depot into the image and remove any installed packages
# not used by our Manifest.toml.
RUN --mount=type=cache,target=/tmp/julia-cache,uid=1000,gid=100 \
    rm ~/.julia && \
    mkdir ~/.julia && \
    cp -rp /tmp/julia-cache/* ~/.julia && \
    julia -e 'using Pkg, Dates; Pkg.gc(; collect_delay=Day(0))'

#####
##### ray-jl stage
#####

FROM ray-base as ray-jl

# Install Bazel and compilers
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
    ln -s /mnt/bazel-cache ~/.cache/bazel

# Install npm
# https://docs.ray.io/en/releases-2.5.1/ray-contribute/development.html#preparing-to-build-ray-on-linux
COPY --from=node:14-bullseye /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node:14-bullseye /usr/local/bin/node /usr/local/bin/
RUN sudo ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
RUN node --version && \
    npm --version

ENV JULIA_PROJECT /Ray.jl
ENV JLL_JULIA_PROJECT=${JULIA_PROJECT}/ray_julia_jll
RUN sudo mkdir -p ${JULIA_PROJECT} && \
    sudo chown ray ${JULIA_PROJECT}

# Install custom Ray CLI which supports the Julia language.
# https://docs.ray.io/en/releases-2.5.1/ray-contribute/development.html#building-ray-on-linux-macos-full
ENV RAY_ROOT=/ray
ARG RAY_COMMIT=0155184
ARG RAY_GEN_CACHE_DIR=/mnt/ray-generated
RUN sudo mkdir -p ${RAY_ROOT} && \
    sudo chown ray ${RAY_ROOT}
RUN --mount=type=cache,sharing=locked,target=/mnt/bazel-cache,uid=1000,gid=100 \
    --mount=type=cache,sharing=locked,target=${RAY_GEN_CACHE_DIR},uid=1000,gid=100 \
    set -eux && \
    git clone https://github.com/beacon-biosignals/ray ${RAY_ROOT} && \
    git --git-dir=${RAY_ROOT}/.git checkout -q ${RAY_COMMIT} && \
    mkdir -p ${JLL_JULIA_PROJECT}/deps && \
    ln -s ${RAY_ROOT} ${JLL_JULIA_PROJECT}/deps/ray  && \
    cd ${JLL_JULIA_PROJECT}/deps/ray && \

    # The Ray `BUILD.bazel` includes a bunch of `copy_to_workspace` rules which copy build output
    # into the Ray worktree. When we only restore the Bazel cache then re-building causes these
    # rules to be skipped resulting in `error: [Errno 2] No such file or directory`. By manually
    # saving/restoring these files we can work around this.
    if [ -d ${RAY_GEN_CACHE_DIR}/python ]; then \
        dest=$(pwd) && \
        cd ${RAY_GEN_CACHE_DIR} && \
        cp -rp --parents \
            python/ray/_raylet.so \
            python/ray/core/generated \
            python/ray/serve/generated \
            python/ray/core/src/ray/raylet/raylet \
            python/ray/core/src/ray/gcs \
            $dest && \
        cd -; \
    fi && \

    # Build the dashboard
    cd ${JLL_JULIA_PROJECT}/deps/ray/python/ray/dashboard/client && \
    npm ci && \
    npm run build && \

    # Build Ray for Python
    cd ${JLL_JULIA_PROJECT}/deps/ray/python && \
    pip install --verbose . && \

    # By copying the entire Ray worktree we can easily restore missing files without having to
    # delete the cache and build from scratch.
    mkdir -p ${RAY_GEN_CACHE_DIR} && \
    cp -rfp ${RAY_ROOT} ${RAY_GEN_CACHE_DIR} && \

    # Remove directory to avoid conflict with a future COPY
    rm -rf ${JLL_JULIA_PROJECT}

# Copy over artifacts generated during the previous stages
COPY --chown=ray --link --from=deps ${HOME}/.julia ${HOME}/.julia

# Setup ray_julia_jll
ENV JLL_ROOT=/ray_julia_jll
COPY --chown=ray ray_julia_jll ${JLL_ROOT}
RUN --mount=type=cache,sharing=locked,target=/mnt/bazel-cache,uid=1000,gid=100 \
    set -eux && \
    ln -s ${RAY_ROOT} ${JLL_ROOT}/deps/ray && \
    ln -s ${JLL_ROOT} ${JLL_JULIA_PROJECT} && \
    julia --project=${JLL_JULIA_PROJECT} -e 'using Pkg; Pkg.build(verbose=true); Pkg.precompile(strict=true)' && \
    cp -rpL ${JLL_JULIA_PROJECT}/deps/bazel-bin ${JLL_JULIA_PROJECT}/deps/bin && \
    rm ${JLL_JULIA_PROJECT}/deps/bazel-* && \
    rm ${JLL_JULIA_PROJECT}

# Overwrite the Overrides.toml created during Pkg.build
COPY --chown=ray <<-EOF ${HOME}/.julia/artifacts/Overrides.toml
[c348cde4-7f22-4730-83d8-6959fb7a17ba]
ray_julia = "${JULIA_PROJECT}/ray_julia_jll/deps/bin"
EOF

COPY --chown=ray . ${JULIA_PROJECT}/

# Restore content from previously built ray_julia_jll directory
RUN rm -rf ${JLL_JULIA_PROJECT} && \
    ln -s ${JLL_ROOT} ${JLL_JULIA_PROJECT}

# Note: The `timing` flag requires Julia 1.9
RUN julia -e 'using Pkg; Pkg.precompile(strict=true, timing=true); using Ray'

# Set up default project and working dir so that users need only pass in the requisite script input args
WORKDIR ${JULIA_PROJECT}

