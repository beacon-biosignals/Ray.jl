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
ObjectID put(std::shared_ptr<Buffer> buffer) {
    auto &driver = CoreWorkerProcess::GetCoreWorker();

    // Store our string in the object store
    ObjectID object_id;
    RayObject ray_obj = RayObject(buffer, nullptr, std::vector<rpc::ObjectReference>());
    RAY_CHECK_OK(driver.Put(ray_obj, {}, &object_id));

    return object_id;
}

// https://github.com/ray-project/ray/blob/a4a8389a3053b9ef0e8409a55e2fae618bfca2be/src/ray/core_worker/test/core_worker_test.cc#L210-L220
std::shared_ptr<Buffer> get(ObjectID object_id) {
    auto &driver = CoreWorkerProcess::GetCoreWorker();

    // Retrieve our data from the object store
    std::vector<std::shared_ptr<RayObject>> results;
    std::vector<ObjectID> get_obj_ids = {object_id};
    RAY_CHECK_OK(driver.Get(get_obj_ids, -1, &results));

    std::shared_ptr<RayObject> result = results[0];
    if (result == nullptr) {
        return nullptr;
    }

    return result->GetData();
}

std::string ToString(ray::FunctionDescriptor function_descriptor)
{
    return function_descriptor->ToString();
}

ray::JuliaFunctionDescriptor function_descriptor(const std::string &mod,
                                                 const std::string &name,
                                                 const std::string &hash) {
    auto fd = FunctionDescriptorBuilder::BuildJulia(mod, name, hash);
    auto ptr = fd->As<JuliaFunctionDescriptor>();
    return *ptr;
}

ray::JuliaFunctionDescriptor GimmeJuliaFunction(ray::FunctionDescriptor function_descriptor) {
    if (!(function_descriptor->Type() == ray::FunctionDescriptorType::kJuliaFunctionDescriptor)) {
        throw std::runtime_error("Cannot convert to JuliaFunctionDescriptor");
    }
    auto ptr = function_descriptor->As<JuliaFunctionDescriptor>();
    return *ptr;
}

JuliaGcsClient::JuliaGcsClient(const gcs::GcsClientOptions &options)
    : options_(options) {
}

JuliaGcsClient::JuliaGcsClient(const std::string &gcs_address) {
    options_ = gcs::GcsClientOptions(gcs_address);
}

Status JuliaGcsClient::Connect() {
    gcs_client_ = std::make_unique<gcs::PythonGcsClient>(options_);
    return gcs_client_->Connect();
}

std::string JuliaGcsClient::Get(const std::string &ns,
                                const std::string &key,
                                int64_t timeout_ms) {
    if (!gcs_client_) {
        throw std::runtime_error("GCS client not initialized; did you forget to Connect?");
    }
    std::string value;
    Status status = gcs_client_->InternalKVGet(ns, key, timeout_ms, value);
    if (!status.ok()) {
        throw std::runtime_error(status.ToString());
    }
    return value;
}

int JuliaGcsClient::Put(const std::string &ns,
                        const std::string &key,
                        const std::string &value,
                        bool overwrite,
                        int64_t timeout_ms) {
    if (!gcs_client_) {
        throw std::runtime_error("GCS client not initialized; did you forget to Connect?");
    }
    int added_num;
    Status status = gcs_client_->InternalKVPut(ns, key, value, overwrite, timeout_ms, added_num);
    if (!status.ok()) {
        throw std::runtime_error(status.ToString());
    }
    return added_num;
}

std::vector<std::string> JuliaGcsClient::Keys(const std::string &ns,
                                              const std::string &prefix,
                                              int64_t timeout_ms) {
    if (!gcs_client_) {
        throw std::runtime_error("GCS client not initialized; did you forget to Connect?");
    }
    std::vector<std::string> results;
    Status status = gcs_client_->InternalKVKeys(ns, prefix, timeout_ms, results);
    if (!status.ok()) {
        throw std::runtime_error(status.ToString());
    }
    return results;
}

bool JuliaGcsClient::Exists(const std::string &ns,
                            const std::string &key,
                            int64_t timeout_ms) {
    if (!gcs_client_) {
        throw std::runtime_error("GCS client not initialized; did you forget to Connect?");
    }
    bool exists;
    Status status = gcs_client_->InternalKVExists(ns, key, timeout_ms, exists);
    if (!status.ok()) {
        throw std::runtime_error(status.ToString());
    }
    return exists;
}

namespace jlcxx
{
    // Needed for upcasting
    template<> struct SuperType<LocalMemoryBuffer> { typedef Buffer type; };

    // Disable generated constructors
    // https://github.com/JuliaInterop/CxxWrap.jl/issues/141#issuecomment-491373720
    template<> struct DefaultConstructible<LocalMemoryBuffer> : std::false_type {};

    // Custom finalizer to show what is being deleted. Can be useful in tracking down
    // segmentation faults due to double deallocations
    // https://github.com/JuliaInterop/CxxWrap.jl/tree/main#overriding-finalization-behavior
    template<typename T>
    struct Finalizer<T, SpecializedFinalizer>
    {
        static void finalize(T* to_delete)
        {
            std::cout << "calling delete on: " << to_delete << std::endl;
            delete to_delete;
        }
    };
}

JLCXX_MODULE define_julia_module(jlcxx::Module& mod)
{
    // WARNING: The order in which register types and methods with jlcxx is important.
    // You must register all function arguments and return types with jlcxx prior to registering
    // the function. If you fail to do this you'll get a "No appropriate factory for type" upon
    // attempting to use the shared library in Julia.

    mod.method("initialize_coreworker", &initialize_coreworker);
    mod.method("shutdown_coreworker", &shutdown_coreworker);
    mod.add_type<ObjectID>("ObjectID");

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
        .method("ToString", &JuliaFunctionDescriptor::ToString)
        .method("ModuleName", &JuliaFunctionDescriptor::ModuleName)
        .method("FunctionName", &JuliaFunctionDescriptor::FunctionName)
        .method("FunctionHash", &JuliaFunctionDescriptor::FunctionHash)
        .method("CallString", &JuliaFunctionDescriptor::CallString);
    // this is a typedef for shared_ptr<FunctionDescriptorInterface>...I wish I
    // could figure out how to de-reference this on the julia side but no dice so
    // far.
    mod.add_type<FunctionDescriptor>("FunctionDescriptor");
    mod.method("GimmeJuliaFunction", &GimmeJuliaFunction);

    mod.method("BuildJulia", &FunctionDescriptorBuilder::BuildJulia);
    mod.method("function_descriptor", &function_descriptor);
    mod.method("ToString", &ToString);

    // class Buffer
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/buffer.h
    mod.add_type<Buffer>("Buffer")
        .method("Data", &Buffer::Data)
        .method("Size", &Buffer::Size)
        .method("OwnsData", &Buffer::OwnsData)
        .method("IsPlasmaBuffer", &Buffer::IsPlasmaBuffer);
    mod.add_type<LocalMemoryBuffer>("LocalMemoryBuffer", jlcxx::julia_base_type<Buffer>());
    mod.method("LocalMemoryBuffer", [] (uint8_t *data, size_t size, bool copy_data = false) {
        return std::make_shared<LocalMemoryBuffer>(data, size, copy_data);
    });

    mod.method("put", &put);
    mod.method("get", &get);

    // mod.add_type<RayObject>("RayObject")
    //     .constructor<const std::shared_ptr<Buffer>,
    //                  const std::shared_ptr<Buffer>,
    //                  const std::vector<rpc::ObjectReference>,
    //                  bool>();

    mod.add_type<Status>("Status")
        .method("ok", &Status::ok)
        .method("ToString", &Status::ToString);
    mod.add_type<JuliaGcsClient>("JuliaGcsClient")
        .constructor<const std::string&>()
        .method("Connect", &JuliaGcsClient::Connect)
        .method("Put", &JuliaGcsClient::Put)
        .method("Get", &JuliaGcsClient::Get)
        .method("Keys", &JuliaGcsClient::Keys)
        .method("Exists", &JuliaGcsClient::Exists);
}

