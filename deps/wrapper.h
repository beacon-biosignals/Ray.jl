#pragma once

#include <string>

#include "jlcxx/jlcxx.hpp"
#include "ray/core_worker/common.h"
#include "ray/core_worker/core_worker.h"
#include "src/ray/protobuf/common.pb.h"
#include "ray/gcs/gcs_client/gcs_client.h"
#include "ray/common/asio/instrumented_io_context.h"

namespace julia {

void initialize_coreworker(int node_manager_port);
void shutdown_coreworker();
ObjectID put(std::string str);
std::string get(ObjectID object_id);

std::string ToString(ray::FunctionDescriptor function_descriptor);

// a wrapper class to manage the IO service + thread that the GcsClient needs.
// we may want to use the PythonGcsClient however, which does not do async
// operations in separate threads as far as I can tell...in which case we would
// not need this wrapper at all.
class JuliaGcsClient {
public:
  JuliaGcsClient(const ray::gcs::GcsClientOptions &options);
  JuliaGcsClient(const std::string &gcs_address);
  ~JuliaGcsClient() { Disconnect(); };

  ray::Status Connect();
  void Disconnect();

  std::string Get(const std::string &ns, const std::string &key);
  void Put(const std::string &ns, const std::string &key, const std::string &val);

  std::unique_ptr<ray::gcs::GcsClient> gcs_client_;
  std::unique_ptr<instrumented_io_context> io_service_;
  std::unique_ptr<std::thread> io_service_thread_;
  ray::gcs::GcsClientOptions options_;
};

JLCXX_MODULE define_julia_module(jlcxx::Module& mod);

}  // namespace julia
