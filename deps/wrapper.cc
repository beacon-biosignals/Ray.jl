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

std::string ToString(ray::FunctionDescriptor function_descriptor)
{
    return function_descriptor->ToString();
}

JuliaGcsClient::JuliaGcsClient(const gcs::GcsClientOptions &options)
  : options_(options) {}

JuliaGcsClient::JuliaGcsClient(const std::string &gcs_address) {
  options_ = gcs::GcsClientOptions(gcs_address);
}

Status JuliaGcsClient::Connect() {
  io_service_ = std::make_unique<instrumented_io_context>();
  io_service_thread_ = std::make_unique<std::thread>([this] {
    std::unique_ptr<boost::asio::io_service::work> work(
        new boost::asio::io_service::work(*io_service_));
    io_service_->run();
  });

  gcs_client_ = std::make_unique<gcs::GcsClient>(options_);
  return gcs_client_->Connect(*io_service_);
}

void JuliaGcsClient::Disconnect() {
  if (io_service_) {
    io_service_->stop();
  }
  if (io_service_thread_ && (io_service_thread_->joinable())) {
    io_service_thread_->join();
  }
  if (gcs_client_) {
    gcs_client_->Disconnect();
    gcs_client_.reset();
  }
}

std::string JuliaGcsClient::Get(const std::string &ns,
                                const std::string &key) {
  RAY_CHECK(gcs_client_);
  auto accessor = gcs_client_->InternalKV();
  std::string value;
  RAY_CHECK_OK(accessor.Get(ns, key, value));
  return value;
}

void JuliaGcsClient::Put(const std::string &ns,
                         const std::string &key,
                         const std::string &value) {
  RAY_CHECK(gcs_client_);
  auto accessor = gcs_client_->InternalKV();
  bool added;
  RAY_CHECK_OK(accessor.Put(ns, key, value, false, added));
  return;
}

JLCXX_MODULE define_julia_module(jlcxx::Module& mod)
{
    mod.method("initialize_coreworker", &initialize_coreworker);
    mod.method("shutdown_coreworker", &shutdown_coreworker);
    mod.add_type<ObjectID>("ObjectID");
    mod.method("put", &put);
    mod.method("get", &get);

    // enum Language
    mod.add_bits<ray::Language>("Language", jlcxx::julia_type("CppEnum"));
    mod.set_const("PYTHON", ray::Language::PYTHON);
    mod.set_const("JAVA", ray::Language::JAVA);
    mod.set_const("CPP", ray::Language::CPP);
    mod.set_const("JULIA", Language::JULIA);

    // enum WorkerType
    mod.add_bits<ray::core::WorkerType>("WorkerType", jlcxx::julia_type("CppEnum"));
    mod.set_const("WORKER", ray::core::WorkerType::WORKER);
    mod.set_const("DRIVER", ray::core::WorkerType::DRIVER);
    mod.set_const("SPILL_WORKER", ray::core::WorkerType::SPILL_WORKER);
    mod.set_const("RESTORE_WORKER", ray::core::WorkerType::RESTORE_WORKER);

    // function descriptors
    // XXX: may not want these in the end, just for interactive testing of the
    // function descriptor stuff.
    mod.add_type<JuliaFunctionDescriptor>("JuliaFunctionDescriptor")
      .method("ToString", &JuliaFunctionDescriptor::ToString);

    // this is a typedef for shared_ptr<FunctionDescriptorInterface>...I wish I
    // could figure out how to de-reference this on the julia side but no dice so
    // far.
    mod.add_type<FunctionDescriptor>("FunctionDescriptor");

    mod.method("BuildJulia", &FunctionDescriptorBuilder::BuildJulia);
    mod.method("ToString", &ToString);

    mod.add_type<Status>("Status")
      .method("ok", &Status::ok)
      .method("ToString", &Status::ToString);
    mod.add_type<JuliaGcsClient>("JuliaGcsClient")
      .constructor<const std::string&>()
      .method("Connect", &JuliaGcsClient::Connect)
      .method("Disconnect", &JuliaGcsClient::Disconnect)
      .method("Put", &JuliaGcsClient::Put)
      .method("Get", &JuliaGcsClient::Get);
}

}  // namespace julia
