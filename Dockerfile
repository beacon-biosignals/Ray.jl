# syntax=docker/dockerfile:1
# Dockerfile is currently only for x86_64

# Example of how to build this Docker image including a recommended tagging structure:
# ```sh
# docker build -t ray:2.5.1-julia_1.9.3-rayjl_$(git rev-parse --short HEAD) .
# ```

# TODO: Cleanup uid/gid/user work arounds

ARG JULIA_VERSION=1.9.3
ARG RAY_VERSION=2.5.1
ARG PYTHON_VERSION=3.10

FROM julia:${JULIA_VERSION}-bullseye as julia-base

FROM python:${PYTHON_VERSION}-bullseye as python-base

# Based upon `/etc/debian_version` the `ray:2.5.1` image is based on Debian Bullseye.
# No automatic multi-architecture support at the moment. Must specify `-aarch64` suffix
# otherwise the default is x86_64 (https://github.com/ray-project/ray/tree/master/docker/ray#tags)
FROM debian:bullseye as ray-base

# Install Python
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get -qq update && \
    apt-get -qq install expat

COPY --from=python-base --link /usr/local/lib/libpython* /usr/local/lib/
COPY --from=python-base --link /usr/local/lib/python3.10 /usr/local/lib/python3.10
COPY --from=python-base --link /usr/local/include/python3.10 /usr/local/include/python3.10
COPY --from=python-base --link /usr/local/bin/python* /usr/local/bin/pip* /usr/local/bin/
RUN python --version && \
    pip --version && \
    # Upgrade pip to ensure that pip is fully functional and up-to-date
    pip install --upgrade pip


# Install Julia
ENV JULIA_PATH=/usr/local/julia
COPY --from=julia-base --link ${JULIA_PATH} ${JULIA_PATH}
RUN ln -s ${JULIA_PATH}/bin/julia /usr/local/bin/julia

# Validate Julia executable is compatible with the container architecture
RUN if ! julia --history-file=no -e 'exit(0)'; then \
        uname -m && \
        readelf -h ${JULIA_PATH}/bin/julia && \
        exit 1; \
    fi

# Reduces output from `apt-get`
ENV DEBIAN_FRONTEND="noninteractive"

# Configure `apt-get` to keep downloaded packages. Needed for using `--mount=type=cache` with `apt-get`
# https://docs.docker.com/engine/reference/builder/#example-cache-apt-packages
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' | tee -a /etc/apt/apt.conf.d/keep-cache

# Install sudo
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get -qq update && \
    apt-get -qq install sudo && \
    echo "%sudo ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create "ray" user
ENV UID=1000
ENV HOME=/home/ray
RUN adduser --uid ${UID} --home ${HOME} --disabled-password --gecos "" ray && \
    adduser ray sudo
USER ray
WORKDIR ${HOME}

# Set x86_64 targets for improved compatibility
# https://docs.julialang.org/en/v1/devdocs/sysimg/#Specifying-multiple-system-image-targets
ENV JULIA_CPU_TARGET="generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)"

# `JULIA_DEPOT_ID` must be unique for every Dockerfile. Typically pre-generated via `openssl rand -hex 5`
ENV JULIA_DEPOT_ID=ab14e38af3
ENV JULIA_USER_DEPOT=/usr/local/share/julia-depot/${JULIA_DEPOT_ID}
ENV JULIA_DEPOT_PATH=${JULIA_USER_DEPOT}

# Allow Julia packages to only be loaded from the current active project. Doing this ensures we don't
# accidentally rely on packages installed into the default Julia environment and avoids issues this can
# cause with Julia depot stacking.
ENV JULIA_LOAD_PATH="@:@stdlib"

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
ARG JULIA_USER_DEPOT_CACHE=/mnt/julia-depot-cache/${JULIA_DEPOT_ID}
RUN sudo mkdir -p $(dirname ${JULIA_USER_DEPOT}) && \
    sudo chown ${UID} $(dirname ${JULIA_USER_DEPOT}) && \
    ln -s ${JULIA_USER_DEPOT_CACHE} ${JULIA_USER_DEPOT}

# Install Julia package registries
RUN --mount=type=cache,target=${JULIA_USER_DEPOT_CACHE},sharing=locked,uid=${UID} \
    mkdir -p ${JULIA_USER_DEPOT_CACHE} && \
    julia -e 'using Pkg; Pkg.Registry.add("General")'

# Instantiate the Julia project environment
ARG RAY_JL_PROJECT=${JULIA_USER_DEPOT}/dev/Ray
COPY --chown=${UID} *Project.toml *Manifest.toml /tmp/Ray.jl/
RUN --mount=type=cache,target=${JULIA_USER_DEPOT_CACHE},sharing=locked,uid=${UID} \
    # Move project content into temporary depot
    rm -rf ${RAY_JL_PROJECT} && \
    mkdir -p $(dirname ${RAY_JL_PROJECT}) && \
    mv /tmp/Ray.jl ${RAY_JL_PROJECT} && \
    # Generate a fake Ray.jl package structure just for instantiation
    mkdir -p ${RAY_JL_PROJECT}/src && touch ${RAY_JL_PROJECT}/src/Ray.jl && \
    # Note: The `timing` flag requires Julia 1.9
    julia --project=${RAY_JL_PROJECT} -e 'using Pkg; Pkg.Registry.update(); Pkg.instantiate(); Pkg.build(); Pkg.precompile(strict=true, timing=true)'

# Copy the shared ephemeral Julia depot into the image and remove any installed packages
# not used by our Manifest.toml.
RUN --mount=type=cache,target=${JULIA_USER_DEPOT_CACHE},uid=${UID} \
    rm ${JULIA_USER_DEPOT} && \
    mkdir ${JULIA_USER_DEPOT} && \
    cp -rp ${JULIA_USER_DEPOT_CACHE}/* ${JULIA_USER_DEPOT} && \
    JULIA_LOAD_PATH=":" julia -e 'using Pkg, Dates; Pkg.gc(collect_delay=Day(0))'

#####
##### build-ray-jl stage
#####

FROM ray-base as build-ray-jl

# Install Bazel and compilers
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    case $(uname -m) in \
        "x86_64")  ARCH=amd64 ;; \
        "aarch64") ARCH=arm64 ;; \
    esac; \
    sudo apt-get -qq update && \
    sudo apt-get -qq install build-essential curl gcc-9 g++-9 pkg-config psmisc unzip git && \
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 \
        --slave /usr/bin/g++ g++ /usr/bin/g++-9 \
        --slave /usr/bin/gcov gcov /usr/bin/gcov-9 && \
    curl -sSLo /tmp/bazel https://github.com/bazelbuild/bazelisk/releases/download/v1.18.0/bazelisk-linux-${ARCH} && \
    sudo install /tmp/bazel /usr/local/bin && \
    rm /tmp/bazel

# Setup user Bazel cache to point to Docker Bazel cache
ARG BAZEL_CACHE=/mnt/bazel-cache
RUN mkdir ~/.cache && \
    ln -s ${BAZEL_CACHE} ~/.cache/bazel

# Install npm
# https://docs.ray.io/en/releases-2.5.1/ray-contribute/development.html#preparing-to-build-ray-on-linux
COPY --from=node:14-bullseye /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node:14-bullseye /usr/local/bin/node /usr/local/bin/
RUN sudo ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
RUN node --version && \
    npm --version

ARG RAY_JL_PROJECT=${JULIA_USER_DEPOT}/dev/Ray
ARG BUILD_PROJECT=${RAY_JL_PROJECT}/build

# Install custom Ray CLI which supports the Julia language.
# https://docs.ray.io/en/releases-2.5.1/ray-contribute/development.html#building-ray-on-linux-macos-full
ARG RAY_REPO=/tmp/ray
ARG RAY_REPO_CACHE=/mnt/ray-cache
ARG RAY_CACHE_CLEAR=false
COPY --chown=${UID} build/ray_commit /tmp/ray_commit
RUN --mount=type=cache,target=${BAZEL_CACHE},sharing=locked,uid=${UID} \
    --mount=type=cache,target=${RAY_REPO_CACHE},sharing=locked,uid=${UID} \
    set -eux && \
    read -r ray_commit < /tmp/ray_commit && \
    git clone https://github.com/beacon-biosignals/ray ${RAY_REPO} && \
    git -C ${RAY_REPO} checkout ${ray_commit} && \
    #
    # Build using the final Ray.jl destination
    sudo mkdir -p ${BUILD_PROJECT} && \
    sudo chown ${UID} ${BUILD_PROJECT} && \
    ln -s ${RAY_REPO} ${BUILD_PROJECT}/ray && \
    cd ${BUILD_PROJECT}/ray && \
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
    cd ${BUILD_PROJECT}/ray/python/ray/dashboard/client && \
    npm ci && \
    npm run build && \
    #
    # Build Ray for Python
    cd ${BUILD_PROJECT}/ray/python && \
    pip install --verbose --user ".[default]" "pydantic<2" && \
    #
    # By copying the entire Ray worktree we can easily restore missing files without having to
    # delete the cache and build from scratch.
    mkdir -p ${RAY_REPO_CACHE} && \
    cp -rfp ${RAY_REPO}/. ${RAY_REPO_CACHE} && \
    #
    # Validate Ray CLI works
    $(python -m site --user-base)/bin/ray --version

# Install additional dependencies for RayCluster support
# https://github.com/ray-project/ray/blob/a03efd9931128d387649dd48b0e4864b43d3bfb4/docker/ray-deps/Dockerfile#L12-L28
RUN pip install --user kubernetes

# Copy over artifacts generated during the previous stages
COPY --from=deps --chown=${UID} --link ${JULIA_USER_DEPOT} ${JULIA_USER_DEPOT}

# Setup ray_julia library
ARG BUILD_ROOT=/tmp/build
COPY --chown=${UID} build ${BUILD_ROOT}
RUN --mount=type=cache,target=${BAZEL_CACHE},sharing=locked,uid=${UID} \
    set -eux && \
    #
    # Build using the final Ray.jl destination
    ln -s ${RAY_REPO} ${BUILD_ROOT}/ray && \
    rm -rf ${BUILD_PROJECT} && \
    ln -s ${BUILD_ROOT} ${BUILD_PROJECT} && \
    #
    # Build ray_julia library
    julia --project=${BUILD_PROJECT} -e 'using Pkg; Pkg.resolve(); Pkg.precompile(strict=true)' && \
    julia --project=${BUILD_PROJECT} ${BUILD_PROJECT}/build_library.jl --no-override && \
    #
    # Cleanup build data
    cp -rpL ${BUILD_ROOT}/bazel-bin ${BUILD_ROOT}/bin && \
    rm ${BUILD_ROOT}/bazel-* && \
    rm ${BUILD_ROOT}/ray && \
    rm ${BUILD_PROJECT}

# Specify the location of the "ray_julia" library via Overrides.toml
COPY --chown=${UID} <<-EOF ${JULIA_USER_DEPOT}/artifacts/Overrides.toml
[3f779ece-f0b6-4c4f-a81a-0cb2add9eb95]
ray_julia = "${BUILD_PROJECT}/bin"
EOF

COPY --chown=${UID} . ${RAY_JL_PROJECT}/

# Restore content from previous build directory
RUN rm -rf ${BUILD_PROJECT} && \
    mv ${BUILD_ROOT} ${BUILD_PROJECT}

# Note: The `timing` flag requires Julia 1.9
RUN julia --project=${RAY_JL_PROJECT} -e 'using Pkg; Pkg.precompile(strict=true, timing=true); using Ray'


#####
##### ray-jl stage
#####

FROM ray-base as ray-jl

# Equivalent of `python -m site --user-base`
ARG PYTHON_USER_BASE=${HOME}/.local

COPY --from=build-ray-jl --link ${PYTHON_USER_BASE} ${PYTHON_USER_BASE}
ENV PATH="${PYTHON_USER_BASE}/bin:${PATH}"
RUN ray --version

ARG RAY_JL_PROJECT=${JULIA_USER_DEPOT}/dev/Ray
COPY --from=build-ray-jl --chown=${UID} --link ${JULIA_USER_DEPOT} ${JULIA_USER_DEPOT}
RUN julia --project=${RAY_JL_PROJECT} -e 'using Ray'

# Set up default project and working dir so that users need only pass in the requisite script input args
ENV JULIA_PROJECT=${RAY_JL_PROJECT}
WORKDIR ${RAY_JL_PROJECT}
