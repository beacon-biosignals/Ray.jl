#pragma once

#include <string>

#include "jlcxx/jlcxx.hpp"
#include "jlcxx/functions.hpp"
#include "jlcxx/stl.hpp"
#include "ray/core_worker/common.h"
#include "ray/core_worker/core_worker.h"
#include "src/ray/protobuf/common.pb.h"
#include "ray/gcs/gcs_client/gcs_client.h"
#include "ray/common/asio/instrumented_io_context.h"
#include "ray/common/ray_object.h"


using namespace ray;
using ray::core::CoreWorkerProcess;
using ray::core::CoreWorkerOptions;
using ray::core::RayFunction;
using ray::core::TaskOptions;
using ray::core::WorkerType;
using ray::RayObject;
using ray::rpc::ObjectReference;

void initialize_coreworker_driver(
    std::string raylet_socket,
    std::string store_socket,
    std::string gcs_address,
    std::string node_ip_address,
    int node_manager_port);

void shutdown_coreworker();
ObjectID put(std::shared_ptr<Buffer> buffer);
std::shared_ptr<Buffer> get(ObjectID object_id);
std::string ToString(ray::FunctionDescriptor function_descriptor);
ObjectID _submit_task(std::string project_dir,
                      const ray::JuliaFunctionDescriptor &func_descriptor,
                      const std::vector<ObjectID> &object_ids);

// a wrapper class to manage the IO service + thread that the GcsClient needs.
// we may want to use the PythonGcsClient however, which does not do async
// operations in separate threads as far as I can tell...in which case we would
// not need this wrapper at all.
class JuliaGcsClient {
public:
    JuliaGcsClient(const ray::gcs::GcsClientOptions &options);
    JuliaGcsClient(const std::string &gcs_address);

    ray::Status Connect();

    std::string Get(const std::string &ns,
                    const std::string &key,
                    int64_t timeout_ms);
    int Put(const std::string &ns,
            const std::string &key,
            const std::string &val,
            bool overwrite,
            int64_t timeout_ms);
    std::vector<std::string> Keys(const std::string &ns,
                                  const std::string &prefix,
                                  int64_t timeout_ms);
    bool Exists(const std::string &ns,
                const std::string &key,
                int64_t timeout_ms);

    std::unique_ptr<ray::gcs::PythonGcsClient> gcs_client_;
    ray::gcs::GcsClientOptions options_;
};

JLCXX_MODULE define_julia_module(jlcxx::Module& mod);
