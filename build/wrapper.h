#pragma once

#include <string>
#include <google/protobuf/message.h>

#include "jlcxx/jlcxx.hpp"
#include "jlcxx/functions.hpp"
#include "jlcxx/stl.hpp"
#include "ray/core_worker/common.h"
#include "ray/core_worker/core_worker.h"
#include "src/ray/protobuf/common.pb.h"
#include "src/ray/protobuf/gcs.pb.h"
#include "ray/gcs/gcs_client/gcs_client.h"
#include "ray/gcs/gcs_client/global_state_accessor.h"
#include "ray/common/asio/instrumented_io_context.h"
#include "ray/common/ray_object.h"
#include "ray/util/logging.h"

using namespace ray;
using ray::core::CoreWorkerProcess;
using ray::core::CoreWorkerOptions;
using ray::core::RayFunction;
using ray::core::TaskOptions;
using ray::core::WorkerType;
std::string ToString(ray::FunctionDescriptor function_descriptor);

// JuliaGCSClient is a wrapper class to manage the IO service + thread that the GcsClient needs.
// https://github.com/beacon-biosignals/ray/blob/448a83caf44108fc1bc44fa7c6c358cffcfcb0d7/src/ray/gcs/gcs_client/gcs_client.h#L61-L87
// Note that connection timeout information, etc. is parsed from the RayConfig parameters:
// https://github.com/ray-project/ray/blob/e060dc2de2251cf883de9b43dda9c73e448e6cbd/src/ray/common/ray_config_def.h
// these can be overwritten via environment variables before initializing the RayConfig / GCSClient, e.g.
// ENV["RAY_gcs_server_request_timeout_seconds"] = 10
// Timeouts that may be useful to configure:
// - gcs_rpc_server_reconnect_timeout_s (default 5): timeout for connecting to GCSClient
// - gcs_rpc_server_reconnect_timeout_s (default 60): timeout for reconnecting to GCSClient
// - gcs_server_request_timeout_seconds (default 60): timeout for fetching from GCSClient
class JuliaGcsClient {
    public:
        JuliaGcsClient(const ray::gcs::GcsClientOptions &options);
        JuliaGcsClient(const std::string &gcs_address);

        ~JuliaGcsClient() {
            // Automatically disconnect a client to avoid a SIGABRT (6)
            // https://github.com/beacon-biosignals/Ray.jl/pull/211#issuecomment-1780070784
            if (gcs_client_) {
                std::cerr << "\x1B[31mWarning: Forgot to disconnect JuliaGcsClient\033[0m" << std::endl;
                this->Disconnect();
            }
        }

        ray::Status Connect();
        void Disconnect();

        // Get, Put, Exists, Keys use methods belonging to an InternalKV field of the GCSClient
        // https://github.com/beacon-biosignals/ray/blob/448a83caf44108fc1bc44fa7c6c358cffcfcb0d7/src/ray/gcs/gcs_client/accessor.h#L687
        std::string Get(const std::string &ns, const std::string &key);

        bool Put(const std::string &ns,
                 const std::string &key,
                 const std::string &value,
                 bool overwrite);

        std::vector<std::string> Keys(const std::string &ns, const std::string &prefix);

        bool Exists(const std::string &ns, const std::string &key);

    private:
        std::unique_ptr<ray::gcs::GcsClient> gcs_client_;
        ray::gcs::GcsClientOptions options_;
        std::unique_ptr<instrumented_io_context> io_service_;
        std::unique_ptr<std::thread> io_service_thread_;
};

JLCXX_MODULE define_julia_module(jlcxx::Module& mod);
