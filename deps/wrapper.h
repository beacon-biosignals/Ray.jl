#pragma once

#include <string>

#include "jlcxx/jlcxx.hpp"
#include "ray/core_worker/common.h"
#include "ray/core_worker/core_worker.h"
#include "src/ray/protobuf/common.pb.h"

namespace julia {

void initialize_coreworker(int node_manager_port);
void shutdown_coreworker();
std::string get(ObjectID object_id);
ObjectID put(std::string str);

JLCXX_MODULE define_julia_module(jlcxx::Module& mod);

}  // namespace julia
