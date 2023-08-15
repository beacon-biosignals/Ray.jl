# NOTES:
#
# python function manager maintains a local table of "execution info" with a
# "function_id" key and values taht are named tuples of name/function/max_calls.
#
# python remote function sets a UUID4 at construction time:
# https://github.com/beacon-biosignals/ray/blob/beacon-main/python/ray/remote_function.py#L128
#
# ...that's used to set the function_hash (???)...
# https://github.com/beacon-biosignals/ray/blob/beacon-main/python/ray/remote_function.py#L263-L265
#
# later comment suggests that "ideally" they'd use the hash of the pickled
# function:
# https://github.com/beacon-biosignals/ray/blob/beacon-main/python/ray/includes/function_descriptor.pxi#L183-L186
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

# python uses "fun" for the namespace: https://github.com/beacon-biosignals/ray/blob/dfk%2Fusing-Ray/python/ray/_private/ray_constants.py#L380
# so "jlfun" seems reasonable
const FUNCTION_MANAGER_NAMESPACE = "jlfun"

Base.@kwdef struct FunctionManager
    gcs_client::JuliaGcsClient
    functions::Dict{String,Any}
end

const FUNCTION_MANAGER = Ref{FunctionManager}()

function function_key(fd::JuliaFunctionDescriptor, job_id=get_current_job_id())
    return string("RemoteFunction:", job_id, ":", fd.function_hash)
end

function export_function!(fm::FunctionManager, f, job_id=get_current_job_id())
    fd = function_descriptor(f)
    key = function_key(fd, job_id)
    if Exists(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE,
              deepcopy(key), # DFK: I _think_ the string memory may be mangled
                             # if we don't copy.  not sure but it can't hurt
              -1)
        @debug "function already present in GCS store:" fd key f
    else
        @debug "exporting function to GCS store:" fd key f
        val = base64encode(serialize, f)
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
function import_function!(fm::FunctionManager, fd::JuliaFunctionDescriptor,
                          job_id=get_current_job_id())
    return get!(fm.functions, fd.function_hash) do
        key = function_key(fd, job_id)
        @debug "retrieving $(fd) from function store with key $(key)"
        val = Get(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE, key, -1)
        try
            io = IOBuffer()
            iob64 = Base64DecodePipe(io)
            write(io, val)
            seekstart(io)
            f = deserialize(iob64)
        catch e
            error("Failed to deserialize function from store: $(fd)")
        end
    end
end
