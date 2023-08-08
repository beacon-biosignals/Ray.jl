#pragma once

#include <string>

#include "jlcxx/jlcxx.hpp"
#include "jlcxx/functions.hpp"
#include "ray/core_worker/common.h"
#include "ray/core_worker/core_worker.h"
#include "src/ray/protobuf/common.pb.h"

using namespace ray;
using ray::core::CoreWorkerProcess;
using ray::core::CoreWorkerOptions;
using ray::core::WorkerType;

void initialize_coreworker(int node_manager_port);
void shutdown_coreworker();
ObjectID put(std::shared_ptr<Buffer> buffer);
std::shared_ptr<Buffer> get(ObjectID object_id);

std::string ToString(ray::FunctionDescriptor function_descriptor);
std::shared_ptr<LocalMemoryBuffer> make_shared_local_memory_buffer(uint8_t *data, size_t size, bool copy_data);

JLCXX_MODULE define_julia_module(jlcxx::Module& mod);
