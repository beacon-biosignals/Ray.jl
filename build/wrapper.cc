#include "wrapper.h"

void initialize_driver(
    std::string raylet_socket,
    std::string store_socket,
    std::string gcs_address,
    std::string node_ip_address,
    int node_manager_port,
    JobID job_id,
    std::string logs_dir,
    const std::string &serialized_job_config) {
    // RAY_LOG_ENABLED(DEBUG);

    CoreWorkerOptions options;
    options.worker_type = WorkerType::DRIVER;
    options.language = Language::JULIA;
    options.store_socket = store_socket;    // Required around `CoreWorkerClientPool` creation
    options.raylet_socket = raylet_socket;  // Required by `RayletClient`
    options.job_id = job_id;
    options.gcs_options = gcs::GcsClientOptions(gcs_address);
    options.enable_logging = !logs_dir.empty();
    options.log_dir = logs_dir;
    // options.install_failure_signal_handler = true;
    options.node_ip_address = node_ip_address;
    options.node_manager_port = node_manager_port;
    options.raylet_ip_address = node_ip_address;
    options.metrics_agent_port = -1;
    options.driver_name = "julia_core_worker_test";

    // `CoreWorkerProcess::Initialize` will create a `WorkerContext` (ray/core_worker/context.h) which
    // is populated with the `JobConfig` specified here.
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/core_worker.cc#L165-L172
    options.serialized_job_config = serialized_job_config;

    CoreWorkerProcess::Initialize(options);
}

void shutdown_driver() {
    CoreWorkerProcess::Shutdown();
}

// https://www.kdab.com/how-to-cast-a-function-pointer-to-a-void/
// https://docs.oracle.com/cd/E19059-01/wrkshp50/805-4956/6j4mh6goi/index.html

void initialize_worker(
    std::string raylet_socket,
    std::string store_socket,
    std::string gcs_address,
    std::string node_ip_address,
    int node_manager_port,
    int64_t startup_token,
    int64_t runtime_env_hash,
    void *julia_task_executor) {

    // XXX: Ideally the task_executor would use a `jlcxx::SafeCFunction` and take the expected
    // callback arg types:
    //   std::vector<std::pair<ObjectID, std::shared_ptr<RayObject>>> *returns
    //   std::vector<std::shared_ptr<RayObject>>
    //   std::string *application_error
    // But for now we just provide void pointers and cast them accordingly in the Julia function.
    // Note also that std::pair is not wrapped by CxxWrap: https://github.com/JuliaInterop/CxxWrap.jl/issues/201
    auto task_executor = reinterpret_cast<void (*)(RayFunction,
                                                   const void*,  // returns
                                                   const void*,  // args
                                                   std::string,  // task_name
                                                   std::string*, // application_error
                                                   bool*         // is_retryable_error
                                                   )>(julia_task_executor);

    CoreWorkerOptions options;
    options.worker_type = WorkerType::WORKER;
    options.language = Language::JULIA;
    options.store_socket = store_socket;    // Required around `CoreWorkerClientPool` creation
    options.raylet_socket = raylet_socket;  // Required by `RayletClient`
    options.gcs_options = gcs::GcsClientOptions(gcs_address);
    // options.enable_logging = true;
    // options.install_failure_signal_handler = true;
    options.node_ip_address = node_ip_address;
    options.node_manager_port = node_manager_port;
    options.raylet_ip_address = node_ip_address;
    options.metrics_agent_port = -1;
    options.startup_token = startup_token;
    options.runtime_env_hash = runtime_env_hash;
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

          std::vector<std::shared_ptr<RayObject>> return_vec;
          task_executor(ray_function,
                        &return_vec, // implicity converts to void *
                        &args,       // implicity converts to void *
                        task_name,
                        application_error,
                        is_retryable_error);

            // TODO: support multiple return values
            // https://github.com/beacon-biosignals/Ray.jl/issues/54
            if (return_vec.size() == 1) {
                (*returns)[0].second = return_vec[0];
                return Status::OK();
            }
            else {
                auto msg = "Task returned " + std::to_string(return_vec.size()) + " values. Expected 1.";
                return Status::NotImplemented(msg);
            };
        };

    RAY_LOG(DEBUG) << "ray_julia_jll: Initializing julia worker coreworker";
    CoreWorkerProcess::Initialize(options);

    RAY_LOG(DEBUG) << "ray_julia_jll: Starting julia worker task execution loop";
    CoreWorkerProcess::RunTaskExecutionLoop();

    RAY_LOG(DEBUG) << "ray_julia_jll: Task execution loop exited";
}

std::vector<std::shared_ptr<RayObject>> *cast_to_returns(void *ptr) {
    auto rayobj_ptr = static_cast<std::vector<std::shared_ptr<RayObject>> *>(ptr);
    return rayobj_ptr;
}

std::vector<std::shared_ptr<RayObject>> cast_to_task_args(void *ptr) {
    auto rayobj_ptr = static_cast<std::vector<std::shared_ptr<RayObject>> *>(ptr);
    return *rayobj_ptr;
}

ObjectID _submit_task(const ray::JuliaFunctionDescriptor &jl_func_descriptor,
                      const std::vector<TaskArg *> &task_args,
                      const std::string &serialized_runtime_env_info,
                      const std::unordered_map<std::string, double> &resources) {

    auto &worker = CoreWorkerProcess::GetCoreWorker();

    ray::FunctionDescriptor func_descriptor = std::make_shared<ray::JuliaFunctionDescriptor>(jl_func_descriptor);
    RayFunction func(Language::JULIA, func_descriptor);

    // TODO: Passing in a `std::vector<std::unique_ptr<TaskArg>>` from Julia may currently be impossible due to:
    // https://github.com/JuliaInterop/CxxWrap.jl/issues/370
    std::vector<std::unique_ptr<TaskArg>> args;
    for (auto &task_arg : task_args) {
        args.emplace_back(task_arg);
    }

    // TaskOptions: https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/common.h#L62-L87
    TaskOptions options;
    options.serialized_runtime_env_info = serialized_runtime_env_info;
    options.resources = resources;

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

ray::core::CoreWorker &_GetCoreWorker() {
    return CoreWorkerProcess::GetCoreWorker();
}

// Example of using `CoreWorker::Put`: https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/test/core_worker_test.cc#L224-L237
Status put(const std::shared_ptr<RayObject> object,
           const std::vector<ObjectID> &contained_object_ids,
           ObjectID *object_id) {

    auto &worker = CoreWorkerProcess::GetCoreWorker();
    // Store our data in the object store
    return worker.Put(*object, contained_object_ids, object_id);
}

// Example of using `CoreWorker::Get`: https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/test/core_worker_test.cc#L210-L220
Status get(const ObjectID object_id, const int64_t timeout_ms, std::shared_ptr<RayObject> *result) {
    auto &worker = CoreWorkerProcess::GetCoreWorker();

    // Retrieve our data from the object store
    std::vector<ObjectID> get_obj_ids = {object_id};
    std::vector<shared_ptr<RayObject>> result_vec;
    auto status = worker.Get(get_obj_ids, timeout_ms, &result_vec);
    *result = result_vec[0];

    // TODO (maybe?): allow multiple return values
    // https://github.com/beacon-biosignals/Ray.jl/issues/54
    auto num_objs = result_vec.size();
    if (num_objs != 1) {
        auto msg = "Requested a single object but instead found " + std::to_string(num_objs) + " objects.";
        status = Status::UnknownError(msg);
    }

    return status;
}

bool contains(const ObjectID object_id) {
    auto &worker = CoreWorkerProcess::GetCoreWorker();
    bool has_object;
    auto status = worker.Contains(object_id, &has_object);
    if (!status.ok()) {
        throw std::runtime_error(status.ToString());
    }
    return has_object;
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

ray::JuliaFunctionDescriptor unwrap_function_descriptor(ray::FunctionDescriptor fd) {
    auto ptr = fd->As<JuliaFunctionDescriptor>();
    return *ptr;
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

Status report_error(std::string *application_error,
                    const std::string &err_msg,
                    double timestamp) {
    auto &worker = CoreWorkerProcess::GetCoreWorker();
    auto const &jobid = worker.GetCurrentJobId();

    // report error to coreworker
    *application_error = err_msg;
    // XXX: for some reason, CxxWrap was mangling the argument types here making
    // this very annoying
    //
    // *is_retryable_error = false;

    // push error to relevant driver
    std::cerr << "jll: pushing error to driver: jobid "
              << jobid
              << " timestamp " << timestamp
              << " " << err_msg << std::endl;
    return worker.PushError(jobid, "task", err_msg, timestamp);
}

// Useful in validating that the `serialized_job_config` set in `initialize_driver` is set. An invalid
// string will not be set and the returned value here will be empty.
std::string get_job_serialized_runtime_env() {
    auto &worker = CoreWorkerProcess::GetCoreWorker();
    auto &worker_context = worker.GetWorkerContext();
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/core_worker.cc#L1786-L1787
    std::string job_serialized_runtime_env = worker_context.GetCurrentJobConfig().runtime_env_info().serialized_runtime_env();
    return job_serialized_runtime_env;
}

std::unordered_map<std::string, double> get_task_required_resources() {
    auto &worker = CoreWorkerProcess::GetCoreWorker();
    auto &worker_context = worker.GetWorkerContext();
    return worker_context.GetCurrentTask()->GetRequiredResources().GetResourceUnorderedMap();
}

void _push_back(std::vector<TaskArg *> &vector, TaskArg *el) {
    vector.push_back(el);
}

namespace jlcxx
{
    // Needed for upcasting
    template<> struct SuperType<LocalMemoryBuffer> { typedef Buffer type; };
    template<> struct SuperType<JuliaFunctionDescriptor> { typedef FunctionDescriptorInterface type; };
    template<> struct SuperType<rpc::Address> { typedef google::protobuf::Message type; };
    template<> struct SuperType<rpc::JobConfig> { typedef google::protobuf::Message type; };
    template<> struct SuperType<rpc::ObjectReference> { typedef google::protobuf::Message type; };
    template<> struct SuperType<TaskArgByReference> { typedef TaskArg type; };
    template<> struct SuperType<TaskArgByValue> { typedef TaskArg type; };

    // Disable generated constructors
    // https://github.com/JuliaInterop/CxxWrap.jl/issues/141#issuecomment-491373720
    template<> struct DefaultConstructible<LocalMemoryBuffer> : std::false_type {};
    template<> struct DefaultConstructible<RayObject> : std::false_type {};
    // template<> struct DefaultConstructible<JuliaFunctionDescriptor> : std::false_type {};
    template<> struct DefaultConstructible<TaskArg> : std::false_type {};

    // Custom finalizer to show what is being deleted. Can be useful in tracking down
    // segmentation faults due to double deallocations
    // https://github.com/JuliaInterop/CxxWrap.jl/tree/main#overriding-finalization-behavior
    /*
    template<typename T>
    struct Finalizer<T, SpecializedFinalizer>
    {
        static void finalize(T* to_delete)
        {
            std::cout << "calling delete on: " << to_delete << std::endl;
            delete to_delete;
        }
    };
    */
}

JLCXX_MODULE define_julia_module(jlcxx::Module& mod)
{
    // WARNING: The order in which register types and methods with jlcxx is important.
    // You must register all function arguments and return types with jlcxx prior to registering
    // the function. If you fail to do this you'll get a "No appropriate factory for type" upon
    // attempting to use the shared library in Julia.

    // Resource map type wrapper
    mod.add_type<std::unordered_map<std::string, double>>("CxxMapStringDouble");
    mod.method("_setindex!", [](std::unordered_map<std::string, double> &map,
                                double val,
                                std::string key) {
        map[key] = val;
        return map;
    });
    mod.method("_getindex", [](std::unordered_map<std::string, double> &map,
                               std::string key) {
        return map[key];
    });
    mod.method("_keys", [](std::unordered_map<std::string, double> &map) {
        std::vector<std::string> keys(map.size());
        for (auto kv : map) {
            keys.push_back(kv.first);
        }
        return keys;
    });

    // enum StatusCode
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/status.h#L81
    mod.add_bits<ray::StatusCode>("StatusCode", jlcxx::julia_type("CppEnum"));
    mod.set_const("OK", ray::StatusCode::OK);
    mod.set_const("OutOfMemory", ray::StatusCode::OutOfMemory);
    mod.set_const("KeyError", ray::StatusCode::KeyError);
    mod.set_const("TypeError", ray::StatusCode::TypeError);
    mod.set_const("Invalid", ray::StatusCode::Invalid);
    mod.set_const("IOError", ray::StatusCode::IOError);
    mod.set_const("UnknownError", ray::StatusCode::UnknownError);
    mod.set_const("NotImplemented", ray::StatusCode::NotImplemented);
    mod.set_const("RedisError", ray::StatusCode::RedisError);
    mod.set_const("TimedOut", ray::StatusCode::TimedOut);
    mod.set_const("Interrupted", ray::StatusCode::Interrupted);
    mod.set_const("IntentionalSystemExit", ray::StatusCode::IntentionalSystemExit);
    mod.set_const("UnexpectedSystemExit", ray::StatusCode::UnexpectedSystemExit);
    mod.set_const("CreationTaskError", ray::StatusCode::CreationTaskError);
    mod.set_const("NotFound", ray::StatusCode::NotFound);
    mod.set_const("Disconnected", ray::StatusCode::Disconnected);
    mod.set_const("SchedulingCancelled", ray::StatusCode::SchedulingCancelled);
    mod.set_const("ObjectExists", ray::StatusCode::ObjectExists);
    mod.set_const("ObjectNotFound", ray::StatusCode::ObjectNotFound);
    mod.set_const("ObjectAlreadySealed", ray::StatusCode::ObjectAlreadySealed);
    mod.set_const("ObjectStoreFull", ray::StatusCode::ObjectStoreFull);
    mod.set_const("TransientObjectStoreFull", ray::StatusCode::TransientObjectStoreFull);
    mod.set_const("GrpcUnavailable", ray::StatusCode::GrpcUnavailable);
    mod.set_const("GrpcUnknown", ray::StatusCode::GrpcUnknown);
    mod.set_const("OutOfDisk", ray::StatusCode::OutOfDisk);
    mod.set_const("ObjectUnknownOwner", ray::StatusCode::ObjectUnknownOwner);
    mod.set_const("RpcError", ray::StatusCode::RpcError);
    mod.set_const("OutOfResource", ray::StatusCode::OutOfResource);
    mod.set_const("ObjectRefEndOfStream", ray::StatusCode::ObjectRefEndOfStream);

    // class Status
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/status.h#L127
    mod.add_type<Status>("Status")
        .method("ok", &Status::ok)
        .method("code", &Status::code)
        .method("message", &Status::message)
        .method("ToString", &Status::ToString);

    // TODO: Make `ObjectID`, `JobID`, and `TaskID` a subclass of `BaseID`.
    // The use of templating makes this more work than normal. For now we'll use an
    // abstract Julia type called `BaseID` to assist with dispatch.
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/id.h#L106

    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/id.h#L261
    mod.method("ObjectIDSize", &ObjectID::Size);
    mod.add_type<ObjectID>("ObjectID", jlcxx::julia_type("BaseID"))
        .method("ObjectIDFromBinary", &ObjectID::FromBinary)
        .method("ObjectIDFromHex", &ObjectID::FromHex)
        .method("ObjectIDFromRandom", &ObjectID::FromRandom)
        .method("ObjectIDFromNil", []() {
            auto id = ObjectID::Nil();
            ObjectID id_deref = id;
            return id_deref;
        })
        .method("Binary", &ObjectID::Binary)
        .method("Hex", &ObjectID::Hex);

    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/id.h#L261
    mod.method("JobIDSize", &JobID::Size);
    mod.add_type<JobID>("JobID", jlcxx::julia_type("BaseID"))
        .method("JobIDFromBinary", &JobID::FromBinary)
        .method("JobIDFromHex", &JobID::FromHex)
        .method("JobIDFromInt", &JobID::FromInt)
        .method("Binary", &JobID::Binary)
        .method("Hex", &JobID::Hex)
        .method("ToInt", &JobID::ToInt);

    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/id.h#L175
    mod.method("TaskIDSize", &TaskID::Size);
    mod.add_type<TaskID>("TaskID", jlcxx::julia_type("BaseID"))
        .method("TaskIDFromBinary", &TaskID::FromBinary)
        .method("TaskIDFromHex", &TaskID::FromHex)
        .method("Binary", &TaskID::Binary)
        .method("Hex", &TaskID::Hex);

    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/id.h#L35
    mod.method("WorkerIDSize", &WorkerID::Size);
    mod.add_type<WorkerID>("WorkerID", jlcxx::julia_type("BaseID"))
        .method("WorkerIDFromBinary", &WorkerID::FromBinary)
        .method("WorkerIDFromHex", [](const std::string hex) {
            UniqueID uid = WorkerID::FromHex(hex);
            return static_cast<WorkerID>(uid);
        })
        .method("Binary", &WorkerID::Binary)
        .method("Hex", &WorkerID::Hex);

    mod.method("NodeIDSize", &NodeID::Size);
    mod.add_type<NodeID>("NodeID", jlcxx::julia_type("BaseID"))
        .method("NodeIDFromBinary", &NodeID::FromBinary)
        .method("NodeIDFromHex", [](const std::string hex) {
            UniqueID uid = NodeID::FromHex(hex);
            return static_cast<NodeID>(uid);
        })
        .method("Binary", &NodeID::Binary)
        .method("Hex", &NodeID::Hex);

    mod.method("initialize_driver", &initialize_driver);
    mod.method("_shutdown_driver", &shutdown_driver);
    mod.method("initialize_worker", &initialize_worker);

    // enum Language
    // https://github.com/beacon-biosignals/ray/blob/ray-2.5.1%2B1/src/ray/protobuf/common.proto#L25
    mod.add_bits<rpc::Language>("Language", jlcxx::julia_type("CppEnum"));
    mod.set_const("PYTHON", rpc::Language::PYTHON);
    mod.set_const("JAVA", rpc::Language::JAVA);
    mod.set_const("CPP", rpc::Language::CPP);
    mod.set_const("JULIA", rpc::Language::JULIA);

    // enum WorkerType
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/protobuf/common.proto#L32
    mod.add_bits<rpc::WorkerType>("WorkerType", jlcxx::julia_type("CppEnum"));
    mod.set_const("WORKER", rpc::WorkerType::WORKER);
    mod.set_const("DRIVER", rpc::WorkerType::DRIVER);
    mod.set_const("SPILL_WORKER", rpc::WorkerType::SPILL_WORKER);
    mod.set_const("RESTORE_WORKER", rpc::WorkerType::RESTORE_WORKER);

    // enum ErrorType
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/protobuf/common.proto#L142
    mod.add_bits<rpc::ErrorType>("ErrorType", jlcxx::julia_type("CppEnum"));
    mod.set_const("WORKER_DIED", rpc::ErrorType::WORKER_DIED);
    mod.set_const("ACTOR_DIED", rpc::ErrorType::ACTOR_DIED);
    mod.set_const("OBJECT_UNRECONSTRUCTABLE", rpc::ErrorType::OBJECT_UNRECONSTRUCTABLE);
    mod.set_const("TASK_EXECUTION_EXCEPTION", rpc::ErrorType::TASK_EXECUTION_EXCEPTION);
    mod.set_const("OBJECT_IN_PLASMA", rpc::ErrorType::OBJECT_IN_PLASMA);
    mod.set_const("TASK_CANCELLED", rpc::ErrorType::TASK_CANCELLED);
    mod.set_const("ACTOR_CREATION_FAILED", rpc::ErrorType::ACTOR_CREATION_FAILED);
    mod.set_const("RUNTIME_ENV_SETUP_FAILED", rpc::ErrorType::RUNTIME_ENV_SETUP_FAILED);
    mod.set_const("OBJECT_LOST", rpc::ErrorType::OBJECT_LOST);
    mod.set_const("OWNER_DIED", rpc::ErrorType::OWNER_DIED);
    mod.set_const("OBJECT_DELETED", rpc::ErrorType::OBJECT_DELETED);
    mod.set_const("DEPENDENCY_RESOLUTION_FAILED", rpc::ErrorType::DEPENDENCY_RESOLUTION_FAILED);
    mod.set_const("OBJECT_UNRECONSTRUCTABLE_MAX_ATTEMPTS_EXCEEDED", rpc::ErrorType::OBJECT_UNRECONSTRUCTABLE_MAX_ATTEMPTS_EXCEEDED);
    mod.set_const("OBJECT_UNRECONSTRUCTABLE_LINEAGE_EVICTED", rpc::ErrorType::OBJECT_UNRECONSTRUCTABLE_LINEAGE_EVICTED);
    mod.set_const("OBJECT_FETCH_TIMED_OUT", rpc::ErrorType::OBJECT_FETCH_TIMED_OUT);
    mod.set_const("LOCAL_RAYLET_DIED", rpc::ErrorType::LOCAL_RAYLET_DIED);
    mod.set_const("TASK_PLACEMENT_GROUP_REMOVED", rpc::ErrorType::TASK_PLACEMENT_GROUP_REMOVED);
    mod.set_const("ACTOR_PLACEMENT_GROUP_REMOVED", rpc::ErrorType::ACTOR_PLACEMENT_GROUP_REMOVED);
    mod.set_const("TASK_UNSCHEDULABLE_ERROR", rpc::ErrorType::TASK_UNSCHEDULABLE_ERROR);
    mod.set_const("ACTOR_UNSCHEDULABLE_ERROR", rpc::ErrorType::ACTOR_UNSCHEDULABLE_ERROR);
    mod.set_const("OUT_OF_DISK_ERROR", rpc::ErrorType::OUT_OF_DISK_ERROR);
    mod.set_const("OBJECT_FREED", rpc::ErrorType::OBJECT_FREED);
    mod.set_const("OUT_OF_MEMORY", rpc::ErrorType::OUT_OF_MEMORY);
    mod.set_const("NODE_DIED", rpc::ErrorType::NODE_DIED);

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

    mod.add_type<FunctionDescriptor>("FunctionDescriptor");

    // function descriptors
    // XXX: may not want these in the end, just for interactive testing of the
    // function descriptor stuff.
    mod.add_type<JuliaFunctionDescriptor>("JuliaFunctionDescriptor", jlcxx::julia_base_type<FunctionDescriptorInterface>())
        .method("ModuleName", &JuliaFunctionDescriptor::ModuleName)
        .method("FunctionName", &JuliaFunctionDescriptor::FunctionName)
        .method("FunctionHash", &JuliaFunctionDescriptor::FunctionHash);

    mod.method("BuildJulia", &FunctionDescriptorBuilder::BuildJulia);
    mod.method("function_descriptor", &function_descriptor);
    mod.method("unwrap_function_descriptor", &unwrap_function_descriptor);
    mod.method("ToString", &ToString);
    mod.method("CallString", &CallString);

    // class RayFunction
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/common.h#L46
    mod.add_type<RayFunction>("RayFunction")
        .constructor<>()
        .constructor<Language, const FunctionDescriptor &>()
        .method("GetLanguage", &RayFunction::GetLanguage)
        .method("GetFunctionDescriptor", &RayFunction::GetFunctionDescriptor);

    // class Buffer
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/buffer.h
    mod.add_type<Buffer>("Buffer")
        .method("Data", &Buffer::Data)
        .method("Size", &Buffer::Size)
        .method("OwnsData", &Buffer::OwnsData)
        .method("IsPlasmaBuffer", &Buffer::IsPlasmaBuffer);
    mod.method("BufferFromNull", [] () {
        return std::shared_ptr<Buffer>(nullptr);
    });
    jlcxx::stl::apply_stl<std::shared_ptr<Buffer>>(mod);

    mod.add_type<LocalMemoryBuffer>("LocalMemoryBuffer", jlcxx::julia_base_type<Buffer>());
    mod.method("LocalMemoryBuffer", [] (uint8_t *data, size_t size, bool copy_data = false) {
        return std::make_shared<LocalMemoryBuffer>(data, size, copy_data);
    });

    // Useful notes on wrapping protobuf messages:
    // - `.proto` file syntax: https://protobuf.dev/programming-guides/proto3/
    // - The protobuf syntax is compiled into C++ code and can be useful to inspect. For example:
    //   "src/ray/protobuf/common.proto" is compiled into "bazel-out/*/bin/src/ray/protobuf/common.pb.h"

    // class Message: public MessageLite
    // https://protobuf.dev/reference/cpp/api-docs/google.protobuf.message/
    // https://protobuf.dev/reference/cpp/api-docs/google.protobuf.message_lite/
    mod.add_type<google::protobuf::Message>("Message")
        .method("SerializeAsString", &google::protobuf::Message::SerializeAsString)
        .method("ParseFromString", &google::protobuf::Message::ParseFromString);

    // https://protobuf.dev/reference/cpp/api-docs/google.protobuf.util.json_util/
    mod.method("JsonStringToMessage", [](const std::string json, google::protobuf::Message *message) {
        google::protobuf::util::JsonStringToMessage(json, message);
    });
    mod.method("MessageToJsonString", [](const google::protobuf::Message &message) {
        std::string json;
        google::protobuf::util::MessageToJsonString(message, &json);
        return json;
    });

    // message Address
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/protobuf/common.proto#L86
    mod.add_type<rpc::Address>("Address", jlcxx::julia_base_type<google::protobuf::Message>())
        .constructor<>()
        .method("raylet_id", &rpc::Address::raylet_id)
        .method("ip_address", &rpc::Address::ip_address)
        .method("port", &rpc::Address::port)
        .method("worker_id", &rpc::Address::worker_id);


    // message JobConfig
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/protobuf/common.proto#L324
    mod.add_type<rpc::JobConfig>("JobConfig", jlcxx::julia_base_type<google::protobuf::Message>());

    // message ObjectReference
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/protobuf/common.proto#L500
    mod.add_type<rpc::ObjectReference>("ObjectReference", jlcxx::julia_base_type<google::protobuf::Message>());
    jlcxx::stl::apply_stl<rpc::ObjectReference>(mod);

    // class RayObject
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/ray_object.h#L28
    mod.add_type<RayObject>("RayObject")
        .method("GetData", &RayObject::GetData)
        .method("GetMetadata", &RayObject::GetMetadata)
        .method("GetSize", &RayObject::GetSize)
        .method("GetNestedRefIds", [](RayObject &obj) {
            std::vector<ObjectID> nested_ids;
            for (const auto &ref : obj.GetNestedRefs()) {
                nested_ids.push_back(ObjectID::FromBinary(ref.object_id()));
            }
            return nested_ids;
        })
        .method("HasData", &RayObject::HasData)
        .method("HasMetadata", &RayObject::HasMetadata);

    // Julia RayObject constructors make shared_ptrs
    mod.method("RayObject", [] (
        const std::shared_ptr<Buffer> &data,
        const std::shared_ptr<Buffer> &metadata,
        const std::vector<rpc::ObjectReference> &nested_refs,
        bool copy_data = false) {

        return std::make_shared<RayObject>(data, metadata, nested_refs, copy_data);
    });
    mod.method("RayObject", [] (const std::shared_ptr<Buffer> &data) {
        return std::make_shared<RayObject>(data, nullptr, std::vector<rpc::ObjectReference>(), false);
    });
    jlcxx::stl::apply_stl<std::shared_ptr<RayObject>>(mod);

    mod.method("put", &put);
    mod.method("get", &get);
    mod.method("contains", &contains);

    mod.add_type<JuliaGcsClient>("JuliaGcsClient")
        .constructor<const std::string&>()
        .method("Connect", &JuliaGcsClient::Connect)
        .method("Put", &JuliaGcsClient::Put)
        .method("Get", &JuliaGcsClient::Get)
        .method("Keys", &JuliaGcsClient::Keys)
        .method("Exists", &JuliaGcsClient::Exists);

    mod.add_type<gcs::GcsClientOptions>("GcsClientOptions")
        .constructor<const std::string&>();

    mod.add_type<gcs::GlobalStateAccessor>("GlobalStateAccessor")
        .constructor<const gcs::GcsClientOptions&>()
        .method("GetNextJobID", &ray::gcs::GlobalStateAccessor::GetNextJobID)
        .method("Connect", &ray::gcs::GlobalStateAccessor::Connect)
        .method("Disconnect", &ray::gcs::GlobalStateAccessor::Disconnect);

    mod.method("report_error", &report_error);

    mod.method("cast_to_returns", &cast_to_returns);
    mod.method("cast_to_task_args", &cast_to_task_args);

    mod.method("get_job_serialized_runtime_env", &get_job_serialized_runtime_env);
    mod.method("get_task_required_resources", &get_task_required_resources);

    // class RayConfig
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/ray_config.h#L60
    //
    // Lambdas required here as otherwise we see the following error:
    // "error: call to non-static member function without an object argument"
    mod.add_type<RayConfig>("RayConfig")
        .method("RayConfigInstance", &RayConfig::instance)
        .method("max_direct_call_object_size", [](RayConfig &config) {
            return config.max_direct_call_object_size();
        })
        .method("task_rpc_inlined_bytes_limit", [](RayConfig &config) {
            return config.task_rpc_inlined_bytes_limit();
        })
        .method("record_ref_creation_sites", [](RayConfig &config) {
            return config.record_ref_creation_sites();
        });

    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/common/task/task_util.h
    mod.add_type<TaskArg>("TaskArg");
    mod.method("_push_back", &_push_back);

    // The Julia types `TaskArgByReference` and `TaskArgByValue` have their default finalizers
    // disabled as these will later be used as `std::unique_ptr`. If these finalizers were enabled
    // we would see segmentation faults due to double deallocations.
    //
    // Note: It is possible to create `std::unique_ptr`s in C++ and return them to Julia however
    // CxxWrap is unable to compile any wrapped functions using `std::vector<std::unique_ptr<TaskArg>>`.
    // We're working around this by using `std::vector<TaskArg *>`.
    // https://github.com/JuliaInterop/CxxWrap.jl/issues/370

    mod.add_type<TaskArgByReference>("TaskArgByReference", jlcxx::julia_base_type<TaskArg>())
        .constructor<const ObjectID &/*object_id*/,
                     const rpc::Address &/*owner_address*/,
                     const std::string &/*call_site*/>(false)
        .method("unique_ptr", [](TaskArgByReference *t) {
            return std::unique_ptr<TaskArgByReference>(t);
        });

    mod.add_type<TaskArgByValue>("TaskArgByValue", jlcxx::julia_base_type<TaskArg>())
        .constructor<const std::shared_ptr<RayObject> &/*value*/>(false)
        .method("unique_ptr", [](TaskArgByValue *t) {
            return std::unique_ptr<TaskArgByValue>(t);
        });

    // ObjectID reference count map wrapper
    typedef std::unordered_map<ObjectID, std::pair<size_t, size_t>> ReferenceCountMap;
    mod.add_type<ReferenceCountMap>("CxxMapObjectIDPairIntInt");
    mod.method("_keys", [](ReferenceCountMap &map) {
        std::vector<ObjectID> keys(map.size());
        for (auto kv : map) {
            keys.push_back(kv.first);
        }
        return keys;
    });
    mod.method("_getindex", [](ReferenceCountMap &map, ObjectID &key) {
        auto val = map[key];
        std::vector<size_t> retval;
        retval.push_back(val.first);
        retval.push_back(val.second);
        return retval;
    });

    // class WorkerContext
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/context.h#L30
    mod.add_type<ray::core::WorkerContext>("WorkerContext")
        .method("GetCurrentJobConfig", &ray::core::WorkerContext::GetCurrentJobConfig);

    // class CoreWorker
    // https://github.com/ray-project/ray/blob/ray-2.5.1/src/ray/core_worker/core_worker.h#L284
    mod.add_type<ray::core::CoreWorker>("CoreWorker")
        .method("GetWorkerContext", &ray::core::CoreWorker::GetWorkerContext)
        .method("GetCurrentJobId", &ray::core::CoreWorker::GetCurrentJobId)
        .method("GetCurrentTaskId", &ray::core::CoreWorker::GetCurrentTaskId)
        .method("GetRpcAddress", &ray::core::CoreWorker::GetRpcAddress)
        .method("GetOwnerAddress", &ray::core::CoreWorker::GetOwnerAddress)
        .method("GetOwnershipInfo", &ray::core::CoreWorker::GetOwnershipInfo)
        .method("GetObjectRefs", &ray::core::CoreWorker::GetObjectRefs)
        .method("RegisterOwnershipInfoAndResolveFuture", &ray::core::CoreWorker::RegisterOwnershipInfoAndResolveFuture)
        // .method("AddLocalReference", &ray::core::CoreWorker::AddLocalReference)
        .method("AddLocalReference", [](ray::core::CoreWorker &worker, ObjectID &object_id) {
            return worker.AddLocalReference(object_id);
        })
        .method("RemoveLocalReference", &ray::core::CoreWorker::RemoveLocalReference)
        .method("GetAllReferenceCounts", &ray::core::CoreWorker::GetAllReferenceCounts);
    mod.method("_GetCoreWorker", &_GetCoreWorker);

    mod.method("_submit_task", &_submit_task);
}
