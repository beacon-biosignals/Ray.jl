# Workspace names should use Java-package-style names:
# https://bazel.build/rules/lib/globals/workspace
workspace(name = "com_github_beacon_biosignals_ray_wrapper")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# http_archive(
#     name = "com_github_ray_project_ray",
#     strip_prefix = "ray-ray-2.5.1",
#     urls = [
#         "https://github.com/ray-project/ray/archive/refs/tags/ray-2.5.1.tar.gz",
#     ],
#     sha256 = "8449075a06dd5d2ffece43835ac26f9027d8a2af788ba9137f00d1c85944f053",
# )

local_repository(
    name = "com_github_ray_project_ray",
    path = "{{{RAY_DIR}}}",
)

# https://groups.google.com/g/bazel-discuss/c/lsbxZxNjJQw/m/NKb7f_eJBwAJ
_JULIA_BUILD_FILE_CONTENT = """\
package(
    default_visibility = [
        "//visibility:public",
    ],
)

cc_library(
    name = "headers",
    hdrs = glob(["julia/**/*.h"]),
    strip_include_prefix = "julia",
)
"""

# TODO: Will eventually use a BinaryBuilder environment to access
# https://github.com/beacon-biosignals/Ray.jl/issues/62
new_local_repository(
    name = "julia",
    path = "{{{JULIA_INCLUDE_DIR}}}",
    build_file_content = _JULIA_BUILD_FILE_CONTENT,
)

_JLCXX_BUILD_FILE_CONTENT = """\
package(
    default_visibility = [
        "//visibility:public",
    ],
)

cc_library(
    name = "headers",
    hdrs = glob(["include/**/*.hpp"]),
    strip_include_prefix = "include",
)
"""

# TODO: Will eventually use a BinaryBuilder environment to access
# `julia --project -e 'using CxxWrap; println(CxxWrap.prefix_path())'`
# https://github.com/beacon-biosignals/Ray.jl/issues/62
new_local_repository(
    name = "libcxxwrap_julia",
    path = "{{{CXXWRAP_PREFIX_DIR}}}",
    build_file_content = _JLCXX_BUILD_FILE_CONTENT,
)

######
###### Transitive dependencies from Ray
######

# The code below is copied from the Ray project WORKSPACE file and just
# modifies labels starting with `//` to be `@com_github_ray_project_ray//`
# (e.g. `sed 's|"//|"@com_github_ray_project_ray//|g' WORKSPACE`)
# https://github.com/ray-project/ray/blob/ray-2.31.0/WORKSPACE#L13-L26

load("@com_github_ray_project_ray//bazel:ray_deps_setup.bzl", "ray_deps_setup")

ray_deps_setup()

load("@com_github_ray_project_ray//bazel:ray_deps_build_all.bzl", "ray_deps_build_all")

ray_deps_build_all()

# This needs to be run after grpc_deps() in ray_deps_build_all() to make
# sure all the packages loaded by grpc_deps() are available. However a
# load() statement cannot be in a function so we put it here.
load("@com_github_grpc_grpc//bazel:grpc_extra_deps.bzl", "grpc_extra_deps")

grpc_extra_deps()


# ---

http_archive(
    name = "rules_python",
    sha256 = "c68bdc4fbec25de5b5493b8819cfc877c4ea299c0dcb15c244c5a00208cde311",
    strip_prefix = "rules_python-0.31.0",
    url = "https://github.com/bazelbuild/rules_python/releases/download/0.31.0/rules_python-0.31.0.tar.gz",
)

load("@rules_python//python:repositories.bzl", "python_register_toolchains")

python_register_toolchains(
    name = "python3_9",
    python_version = "3.9",
    register_toolchains = False,
)
