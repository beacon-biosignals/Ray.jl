#pragma once

#include <string>

#include "jlcxx/jlcxx.hpp"
#include "ray/core_worker/common.h"
#include "ray/core_worker/core_worker.h"
#include "src/ray/protobuf/common.pb.h"

namespace julia {

std::string put_get(std::string str, int node_manager_port);
JLCXX_MODULE define_julia_module(jlcxx::Module& mod);

}  // namespace julia
