# TODO: this should probably be moved to a Ray.jl package

# NOTES:
#
# python function manager maintains a local table of "execution info" with a
# "function_id" key and values taht are named tuples of name/function/max_calls.
#
# python remote function sets a UUID4 at construction time that's used to set
# the function_hash (???)...comment suggests that "ideally" they'd use the hash
# of the pickled function but that it's not stable for some reason.
# but.....neither is a random UUID?????
#
# the function table key is built like
# <key type>:<jobid>:key

# function manager holds:
# local cache of functions (keyed by function id/hash from descriptor)
# gcs client
# maybe job id?

using ray_core_worker_julia_jll: JuliaGcsClient, Exists, Put, Get, JuliaFunctionDescriptor, function_descriptor

# XXX: what's the actual namespace to use?  probably set per-job but I dunno.
const FUNCTION_MANAGER_NAMESPACE = "JuliaFunctions"

# TODO: remove indirection after fields are settled
Base.@kwdef struct FunctionManager1
    gcs_client::JuliaGcsClient
    functions::Dict{String,Any}
end

# TODO: remove indirection after fields are settled
FunctionManager = FunctionManager1

# XXX: we should probably be packaging task-related metadata like the job_id in
# a task/remotefunction-like struct instead of passing it around like this.
function_key(fd::JuliaFunctionDescriptor, job_id) = string("RemoteFunction:", job_id, ":", fd.function_hash)

function export_function!(fm::FunctionManager, f, job_id)
    fd = function_descriptor(f)
    key = function_key(fd, job_id)
    if Exists(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE, key, -1)
        @debug "function already present in GCS store:" key f
    else
        @debug "exporting function to GCS store:" key f
        val = base64encode(serialize, f)
        Put(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE, key, val, true, -1)
    end
end

# XXX: this will error if the function is not found in the store.
function import_function!(fm::FunctionManager, fd::JuliaFunctionDescriptor, job_id)
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
