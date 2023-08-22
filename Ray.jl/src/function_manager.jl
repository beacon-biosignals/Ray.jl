# NOTES:
#
# python function manager maintains a local table of "execution info" with a
# "function_id" key and values that are named tuples of name/function/max_calls.
#
# python remote function sets a UUID4 at construction time:
# https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/python/ray/remote_function.py#L128
#
# ...that's used to set the function_hash (???)...
# https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/python/ray/remote_function.py#L263-L265
#
# later comment suggests that "ideally" they'd use the hash of the pickled
# function:
# https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/python/ray/includes/function_descriptor.pxi#L183-L186
#
# ...but that it's not stable for some reason.  but.....neither is a random
# UUID?????
#
# the function table key is built like
# <key type>:<jobid>:key

# function manager holds:
# local cache of functions (keyed by function id/hash from descriptor)
# gcs client
# ~~maybe job id?~~ this is managed by the core worker process

using ray_core_worker_julia_jll: JuliaGcsClient, Exists, Put, Get,
                                 JuliaFunctionDescriptor, function_descriptor

const FUNCTION_SIZE_WARN_THRESHOLD = 10_000_000
const FUNCTION_SIZE_ERROR_THRESHOLD = 100_000_000

_mib_string(len) = string(div(len, 1024 * 1024), " MiB")

function check_oversized_function(serialized, function_descriptor)
    len = length(serialized)
    check_msg = "Check that its definition is not implicitly capturing a large " *
                "array or other object in scope. Tip: use `Ray.put()` to put large " *
                "objects in the Ray object store."
    if len > FUNCTION_SIZE_ERROR_THRESHOLD
        msg = "The function $(rayjll.CallString(function_descriptor)) is too " *
              "large ($(_mib_string(len))); FUNCTION_SIZE_ERROR_THRESHOLD=" *
              "$(_mib_string(FUNCTION_SIZE_ERROR_THRESHOLD)). " * check_msg
        throw(ArgumentError(msg))
    elseif len > FUNCTION_SIZE_WARN_THRESHOLD
        msg = "The function $(rayjll.CallString(function_descriptor)) is very " *
              "large ($(_mib_string(len))). " * check_msg
        @warn msg
        # TODO: push warning message to driver if this is a worker
    end
    return nothing
end

# python uses "fun" for the namespace: https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/python/ray/_private/ray_constants.py#L380
# so "jlfun" seems reasonable
const FUNCTION_MANAGER_NAMESPACE = "jlfun"

Base.@kwdef struct FunctionManager
    gcs_client::JuliaGcsClient
    functions::Dict{String,Any}
end

const FUNCTION_MANAGER = Ref{FunctionManager}()

function _init_global_function_manager(gcs_address)
    @info "connecting function manager to GCS at $gcs_address..."
    gcs_client = JuliaGcsClient(gcs_address)
    rayjll.Connect(gcs_client)
    FUNCTION_MANAGER[] = FunctionManager(; gcs_client,
                                         functions=Dict{String,Any}())
end

function function_key(fd::JuliaFunctionDescriptor, job_id=get_current_job_id())
    return string("RemoteFunction:", job_id, ":", fd.function_hash)
end

function export_function!(fm::FunctionManager, f, job_id=get_current_job_id())
    fd = function_descriptor(f)
    key = function_key(fd, job_id)
    @debug "exporting function to function store:" fd key
    if Exists(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE,
              deepcopy(key), # DFK: I _think_ the string memory may be mangled
                             # if we don't copy.  not sure but it can't hurt
              -1)
        @debug "function already present in GCS store:" fd key f
    else
        @debug "exporting function to GCS store:" fd key f
        val = base64encode(serialize, f)
        check_oversized_function(val, fd)
        Put(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE, key, val, true, -1)
    end
end

function wait_for_function(fm::FunctionManager, fd::JuliaFunctionDescriptor,
                           job_id=get_current_job_id();
                           pollint_s=0.01, timeout_s=10)
    key = function_key(fd, job_id)
    status = timedwait(timeout_s; pollint=pollint_s) do
        # timeout the Exists query to the same timeout we use here so we don't
        # deadlock.
        Exists(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE, key, timeout_s)
    end
    return status
end

# XXX: this will error if the function is not found in the store.
# TODO: consider _trying_ to resolve the function descriptor locally (i.e.,
# somthing like `eval(Meta.parse(CallString(fd)))`), falling back to the function
# store only if needed.
function import_function!(fm::FunctionManager, fd::JuliaFunctionDescriptor,
                          job_id=get_current_job_id())
    return get!(fm.functions, fd.function_hash) do
        key = function_key(fd, job_id)
        @debug "function not found locally, retrieving from function store" fd key
        val = Get(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE, key, -1)
        try
            io = IOBuffer()
            iob64 = Base64DecodePipe(io)
            write(io, val)
            seekstart(io)
            f = deserialize(iob64)
            # need to handle world-age issues on remote workers when
            # deserializing the function effectively defines it
            return (args...) -> Base.invokelatest(f, args...)
        catch e
            error("Failed to deserialize function from store: $(fd)")
        end
    end
end
