#include "wrapper.h"

const std::string NODE_MANAGER_IP_ADDRESS = "127.0.0.1";

void initialize_coreworker(int node_manager_port) {
    // RAY_LOG_ENABLED(DEBUG);

    CoreWorkerOptions options;
    options.worker_type = WorkerType::DRIVER;
    options.language = Language::JULIA;
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

// https://www.kdab.com/how-to-cast-a-function-pointer-to-a-void/
// https://docs.oracle.com/cd/E19059-01/wrkshp50/805-4956/6j4mh6goi/index.html

void initialize_coreworker_worker(int node_manager_port, jlcxx::SafeCFunction julia_task_executor
                                  ) {
    // auto task_executor = jlcxx::make_function_pointer<int(
    //     RayFunction
    //     // const std::vector<std::shared_ptr<RayObject>> &args,
    //     // std::vector<std::pair<ObjectID, std::shared_ptr<RayObject>>> *returns
    // )>(julia_task_executor);

    jlcxx::JuliaFunction task_executor("task_executor", "ray_core_worker_julia_jll");

    CoreWorkerOptions options;
    options.worker_type = WorkerType::WORKER;
    options.language = Language::JULIA;
    options.store_socket = "/tmp/ray/session_latest/sockets/plasma_store"; // Required around `CoreWorkerClientPool` creation
    options.raylet_socket = "/tmp/ray/session_latest/sockets/raylet";  // Required by `RayletClient`
    // options.job_id = JobID::FromInt(-1);  // For workers, the job ID is assigned by Raylet via an environment variable.
    options.gcs_options = gcs::GcsClientOptions(NODE_MANAGER_IP_ADDRESS + ":6379");
    // options.enable_logging = true;
    // options.install_failure_signal_handler = true;
    options.node_ip_address = NODE_MANAGER_IP_ADDRESS;
    options.node_manager_port = node_manager_port;
    options.raylet_ip_address = NODE_MANAGER_IP_ADDRESS;
    options.metrics_agent_port = -1;
    options.startup_token = 0;
    options.task_execution_callback =
        [task_executor](
            const rpc::Address &caller_address,
            TaskType task_type,
            const std::string task_name,
            const RayFunction &ray_function,
            const std::unordered_map<std::string, double> &required_resources,
            const std::vector<std::shared_ptr<RayObject>> &args,
            const std::vector<rpc::ObjectReference> &arg_refs,
            const std::string &debugger_breakpoint,
            const std::string &serialized_retry_exception_allowlist,
            std::vector<std::pair<ObjectID, std::shared_ptr<RayObject>>> *returns,
            std::vector<std::pair<ObjectID, std::shared_ptr<RayObject>>> *dynamic_returns,
            std::shared_ptr<LocalMemoryBuffer> &creation_task_exception_pb_bytes,
            bool *is_retryable_error,
            std::string *application_error,
            const std::vector<ConcurrencyGroup> &defined_concurrency_groups,
            const std::string name_of_concurrency_group_to_execute,
            bool is_reattempt,
            bool is_streaming_generator) {
            // task_executor(ray_function, returns, args);
            task_executor(caller_address,
                          task_type,
                          task_name,
                          ray_function,
                          // required_resources,
                          args,
                          arg_refs,
                          debugger_breakpoint,
                          serialized_retry_exception_allowlist,
                          returns,
                          dynamic_returns,
                          creation_task_exception_pb_bytes,
                          is_retryable_error,
                          application_error,
                          defined_concurrency_groups,
                          name_of_concurrency_group_to_execute,
                          is_reattempt,
                          is_streaming_generator);
            return Status::OK();
        };
    CoreWorkerProcess::Initialize(options);

    CoreWorkerProcess::RunTaskExecutionLoop();
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

std::string CallString(ray::FunctionDescriptor function_descriptor)
{
    return function_descriptor->CallString();
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

// TODO (omus): Ideally we would only pass in a `JuliaFunctionDescriptor`
ObjectID _submit_task(std::string project_dir, const ray::FunctionDescriptor &func_descriptor) {
    auto &worker = CoreWorkerProcess::GetCoreWorker();

    RayFunction func(Language::JULIA, func_descriptor);

    // TODO: These args are currently being ignored
    std::vector<std::unique_ptr<TaskArg>> args;
    std::string str = "hello";
    auto buffer = std::make_shared<LocalMemoryBuffer>(reinterpret_cast<uint8_t *>(&str[0]), str.size(), true);
    auto ray_obj = std::make_shared<RayObject>(buffer, nullptr, std::vector<rpc::ObjectReference>());
    args.emplace_back(new TaskArgByValue(ray_obj));

    TaskOptions options;

    // TaskOptions: https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/common.h#L62-L87
    // RuntimeEnvInfo (`options.serialized_runtime_env_info`): https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/protobuf/runtime_env_common.proto#L39-L46
    // RuntimeEnvContext (`{"serialized_runtime_env": ...}`): https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_private/runtime_env/context.py#L20-L45
    options.serialized_runtime_env_info = "{\"serialized_runtime_env\": \"{\\\"env_vars\\\": {\\\"JULIA_PROJECT\\\": \\\"" + project_dir + "\\\"}}\"}";

    rpc::SchedulingStrategy scheduling_strategy;
    scheduling_strategy.mutable_default_scheduling_strategy();

    // https://github.com/ray-project/ray/blob/4e9e8913a6c9cc3533fe27478f30bdee1deffaf5/src/ray/core_worker/test/core_worker_test.cc#L79
    auto return_refs = worker.SubmitTask(
        func,
        args,
        options,
        /*max_retries=*/0,
        /*retry_exceptions=*/false,
        scheduling_strategy,
        /*debugger_breakpoint=*/""
    );

    return ObjectRefsToIds(return_refs)[0];
}

namespace jlcxx
{
    // Needed for upcasting
    template<> struct SuperType<LocalMemoryBuffer> { typedef Buffer type; };
    template<> struct SuperType<JuliaFunctionDescriptor> { typedef FunctionDescriptorInterface type; };

    // Disable generated constructors
    // https://github.com/JuliaInterop/CxxWrap.jl/issues/141#issuecomment-491373720
    template<> struct DefaultConstructible<LocalMemoryBuffer> : std::false_type {};
    // template<> struct DefaultConstructible<JuliaFunctionDescriptor> : std::false_type {};

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
    mod.method("initialize_coreworker_worker", &initialize_coreworker_worker);
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

    // Needed by FunctionDescriptorInterface
    mod.add_bits<ray::rpc::FunctionDescriptor::FunctionDescriptorCase>("FunctionDescriptorCase");

    // class FunctionDescriptorInterface
    mod.add_type<FunctionDescriptorInterface>("FunctionDescriptorInterface")
        .method("Type", &FunctionDescriptorInterface::Type)
        .method("Hash", &FunctionDescriptorInterface::Hash)
        .method("ToString", &FunctionDescriptorInterface::ToString)
        .method("CallSiteString", &FunctionDescriptorInterface::CallSiteString)
        .method("CallString", &FunctionDescriptorInterface::CallString)
        .method("ClassName", &FunctionDescriptorInterface::ClassName)
        .method("DefaultTaskName", &FunctionDescriptorInterface::DefaultTaskName);

    // this is a typedef for shared_ptr<FunctionDescriptorInterface>...I wish I
    // could figure out how to de-reference this on the julia side but no dice so
    // far.
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/function_descriptor.h#L274
    mod.add_type<FunctionDescriptor>("FunctionDescriptor");

    // function descriptors
    // XXX: may not want these in the end, just for interactive testing of the
    // function descriptor stuff.
    mod.add_type<JuliaFunctionDescriptor>("JuliaFunctionDescriptor", jlcxx::julia_base_type<FunctionDescriptorInterface>());
        // .method("JuliaFunctionDescriptor", [] (std::shared_ptr<FunctionDescriptorInterface> fd) {
        //     return reinterpret_cast<JuliaFunctionDescriptor *>(fd);
        // });

    mod.method("BuildJulia", &FunctionDescriptorBuilder::BuildJulia);
    mod.method("ToString", &ToString);
    mod.method("CallString", &CallString);

    // class RayFunction
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/common.h#L46
    mod.add_type<RayFunction>("RayFunction")
        .constructor<>()
        .constructor<Language, const FunctionDescriptor &>()
        .method("GetLanguage", &RayFunction::GetLanguage)
        .method("GetFunctionDescriptor", &RayFunction::GetFunctionDescriptor);

    // types needed for task execution callback args
    mod.add_type<rpc::Address>("Address");
    mod.add_type<rpc::ObjectReference>("ObjectReference");
    mod.add_type<ConcurrencyGroup>("ConcurrencyGroup");

    mod.add_bits<TaskType>("TaskType", jlcxx::julia_type("CppEnum"));
    mod.set_const("NORMAL_TASK", TaskType::NORMAL_TASK);
    mod.set_const("ACTOR_CREATION_TASK", TaskType::ACTOR_CREATION_TASK);
    mod.set_const("ACTOR_TASK", TaskType::ACTOR_TASK);
    mod.set_const("DRIVER_TASK", TaskType::DRIVER_TASK);

    // mod.add_type<jlcxx::Parametric<jlcxx::TypeVar<1>, jlcxx::TypeVar<2>>>("std::unordered_map")
    //     .apply<std::unordered_map<std::string,double>>([](auto wrapped) {
    //         typedef typename decltype(wrapped)::type WrappedT;
    //         wrapped.method("cxxgetindex", &WrappedT::operator[]);
    //     });

    typedef std::unordered_map<std::string, double> RequiredResourceMap;
    mod.add_type<RequiredResourceMap>("RequiredResourceMap")
        .method("cxxgetindex", &RequiredResourceMap::operator[]);

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
    mod.method("_submit_task", &_submit_task);

    mod.add_type<RayObject>("RayObject");
    //     .constructor<const std::shared_ptr<Buffer>,
    //                  const std::shared_ptr<Buffer>,
    //                  const std::vector<rpc::ObjectReference>,
    //                  bool>();

    mod.add_type<Status>("Status")
        .method("ok", &Status::ok)
        .method("OK", &Status::OK)
        .method("ToString", &Status::ToString);
    mod.add_type<JuliaGcsClient>("JuliaGcsClient")
        .constructor<const std::string&>()
        .method("Connect", &JuliaGcsClient::Connect)
        .method("Put", &JuliaGcsClient::Put)
        .method("Get", &JuliaGcsClient::Get)
        .method("Keys", &JuliaGcsClient::Keys)
        .method("Exists", &JuliaGcsClient::Exists);
}

