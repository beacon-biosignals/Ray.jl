#include "wrapper.h"

namespace julia {

using namespace ray;
using ray::core::CoreWorkerProcess;
using ray::core::CoreWorkerOptions;
using ray::core::WorkerType;

const std::string NODE_MANAGER_IP_ADDRESS = "127.0.0.1";

void initialize_coreworker(int node_manager_port) {
    // RAY_LOG_ENABLED(DEBUG);

    CoreWorkerOptions options;
    options.worker_type = WorkerType::DRIVER;
    options.language = Language::PYTHON;
    options.store_socket = "/tmp/ray/session_latest/sockets/plasma_store"; // Required around `CoreWorkerClientPool` creation
    options.raylet_socket = "/tmp/ray/session_latest/sockets/raylet";  // Required by `RayletClient`
    options.job_id = JobID::FromInt(1001);
    options.gcs_options = gcs::GcsClientOptions(NODE_MANAGER_IP_ADDRESS + ":6379");
    // options.enable_logging = true;
    // options.install_failure_signal_handler = true;
    options.node_ip_address = NODE_MANAGER_IP_ADDRESS;
    options.node_manager_port = node_manager_port;
    options.raylet_ip_address = NODE_MANAGER_IP_ADDRESS;
    options.metrics_agent_port = -1;
    options.driver_name = "julia_core_worker_test";
    CoreWorkerProcess::Initialize(options);
}

void shutdown_coreworker() {
    CoreWorkerProcess::Shutdown();
}

// https://github.com/ray-project/ray/blob/a4a8389a3053b9ef0e8409a55e2fae618bfca2be/src/ray/core_worker/test/core_worker_test.cc#L224-L237
ObjectID put(std::string str) {
    auto &driver = CoreWorkerProcess::GetCoreWorker();

    // Store our string in the object store
    ObjectID object_id;
    auto buffer = std::make_shared<LocalMemoryBuffer>(reinterpret_cast<uint8_t *>(&str[0]), str.size(), true);
    RayObject ray_obj = RayObject(buffer, nullptr, std::vector<rpc::ObjectReference>());
    RAY_CHECK_OK(driver.Put(ray_obj, {}, &object_id));

    return object_id;
}

// https://github.com/ray-project/ray/blob/a4a8389a3053b9ef0e8409a55e2fae618bfca2be/src/ray/core_worker/test/core_worker_test.cc#L210-L220
std::string get(ObjectID object_id) {
    auto &driver = CoreWorkerProcess::GetCoreWorker();

    // Retrieve our data from the object store
    std::vector<std::shared_ptr<RayObject>> results;
    std::vector<ObjectID> get_obj_ids = {object_id};
    RAY_CHECK_OK(driver.Get(get_obj_ids, -1, &results));

    std::shared_ptr<RayObject> result = results[0];
    if (result == nullptr) {
        return "\0";
    }

    std::string data = (std::string) reinterpret_cast<char *>(result->GetData()->Data());
    return data;
}

JuliaFunctionDescriptor build_julia_function_descriptor(std::string module_name,
                                                        std::string function_name,
                                                        std::string function_hash)
{
  FunctionDescriptor my_func;
  my_func = FunctionDescriptorBuilder::BuildJulia(module_name, function_name, function_hash);
  // de-reference the returned pointer.
  return static_cast<const JuliaFunctionDescriptor &>(*my_func);
}

JLCXX_MODULE define_julia_module(jlcxx::Module& mod)
{
    mod.method("initialize_coreworker", &initialize_coreworker);
    mod.method("shutdown_coreworker", &shutdown_coreworker);
    mod.add_type<ObjectID>("ObjectID");
    mod.method("put", &put);
    mod.method("get", &get);

    // XXX: may not want these in the end, just for interactive testing of the
    // function descriptor stuff.
    mod.add_type<JuliaFunctionDescriptor>("JuliaFunctionDescriptor")
      .method("ToString", &JuliaFunctionDescriptor::ToString);

    // this is a typedef for shared_ptr<FunctionDescriptorInterface>...I wish I
    // could figure out how to de-reference this on the julia side but no dice so
    // far.
    mod.add_type<FunctionDescriptor>("FunctionDescriptor");

    mod.method("build_julia_function_descriptor", &build_julia_function_descriptor);
    mod.method("BuildJulia", &FunctionDescriptorBuilder::BuildJulia);
}

}  // namespace julia
