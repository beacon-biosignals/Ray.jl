#include "wrapper.h"

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
ObjectID put(void *ptr, size_t size) {
    auto &driver = CoreWorkerProcess::GetCoreWorker();

    // Store our string in the object store
    ObjectID object_id;
    auto shared_buffer = std::make_shared<LocalMemoryBuffer>(reinterpret_cast<uint8_t *>(ptr), size, true);
    RayObject ray_obj = RayObject(shared_buffer, nullptr, std::vector<rpc::ObjectReference>());
    RAY_CHECK_OK(driver.Put(ray_obj, {}, &object_id));

    return object_id;
}

// https://github.com/ray-project/ray/blob/a4a8389a3053b9ef0e8409a55e2fae618bfca2be/src/ray/core_worker/test/core_worker_test.cc#L210-L220
void *get(ObjectID object_id) {
    auto &driver = CoreWorkerProcess::GetCoreWorker();

    // Retrieve our data from the object store
    std::vector<std::shared_ptr<RayObject>> results;
    std::vector<ObjectID> get_obj_ids = {object_id};
    RAY_CHECK_OK(driver.Get(get_obj_ids, -1, &results));

    std::shared_ptr<RayObject> result = results[0];
    if (result == nullptr) {
        return nullptr;
    }

    return result->GetData()->Data();
}

std::string ToString(ray::FunctionDescriptor function_descriptor)
{
    return function_descriptor->ToString();
}

LocalMemoryBuffer *demo(LocalMemoryBuffer *buffer) {
    return buffer;
}

namespace jlcxx
{
    // Needed for upcasting
    template<> struct SuperType<LocalMemoryBuffer> { typedef Buffer type; };
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

    // class Buffer
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/buffer.h
    mod.add_type<Buffer>("Buffer")
        .method("_data_pointer", &Buffer::Data)
        .method("_sizeof", &Buffer::Size)  // TODO: How can we extend a method in Base?
        .method("owns_data", &Buffer::OwnsData)
        .method("is_plasma_buffer", &Buffer::IsPlasmaBuffer);
    mod.add_type<LocalMemoryBuffer>("LocalMemoryBuffer", jlcxx::julia_base_type<Buffer>())
        .constructor<uint8_t *, size_t, bool>();

    // mod.method("demo", &demo);
    mod.method("demo", [] (LocalMemoryBuffer *b) { return demo(b); });

    // mod.add_type<RayObject>("RayObject")
    //     .constructor<const std::shared_ptr<Buffer>,
    //                  const std::shared_ptr<Buffer>,
    //                  const std::vector<rpc::ObjectReference>,
    //                  bool>();
}

