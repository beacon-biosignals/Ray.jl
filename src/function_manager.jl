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

# https://github.com/beacon-biosignals/ray/blob/1c0cddc478fa33d4c244d3c30aba861a77b0def9/python/ray/_private/ray_constants.py#L122-L123
const FUNCTION_SIZE_WARN_THRESHOLD = 10_000_000  # in bytes
const FUNCTION_SIZE_ERROR_THRESHOLD = 100_000_000  # in bytes

_mib_string(num_bytes) = string(div(num_bytes, 1024 * 1024), " MiB")
# https://github.com/beacon-biosignals/ray/blob/1c0cddc478fa33d4c244d3c30aba861a77b0def9/python/ray/_private/utils.py#L744-L746
const _check_msg = "Check that its definition is not implicitly capturing a large " *
                   "array or other object in scope. Tip: use `Ray.put()` to put large " *
                   "objects in the Ray object store."

function check_oversized_function(serialized, function_descriptor)
    len = length(serialized)
    if len > FUNCTION_SIZE_ERROR_THRESHOLD
        msg = "The function $(ray_jll.CallString(function_descriptor)) is too " *
              "large ($(_mib_string(len))); FUNCTION_SIZE_ERROR_THRESHOLD=" *
              "$(_mib_string(FUNCTION_SIZE_ERROR_THRESHOLD)). " * _check_msg
        throw(ArgumentError(msg))
    elseif len > FUNCTION_SIZE_WARN_THRESHOLD
        msg = "The function $(ray_jll.CallString(function_descriptor)) is very " *
              "large ($(_mib_string(len))). " * _check_msg
        @warn msg
        # TODO: push warning message to driver if this is a worker
        # https://github.com/beacon-biosignals/Ray.jl/issues/59
    end
    return nothing
end

# python uses "fun" for the namespace: https://github.com/beacon-biosignals/ray/blob/7ad1f47a9c849abf00ca3e8afc7c3c6ee54cda43/python/ray/_private/ray_constants.py#L380
# so "jlfun" seems reasonable
const FUNCTION_MANAGER_NAMESPACE = "jlfun"

Base.@kwdef mutable struct FunctionManager
    gcs_client::ray_jll.JuliaGcsClient
    functions::Dict{String,Any}

    function FunctionManager(gcs_client, functions)
        fm = new(gcs_client, functions)
        f(x) = ray_jll.Disconnect(x.gcs_client)
        return finalizer(f, fm)
    end
end


const FUNCTION_MANAGER = Ref{FunctionManager}()

function _init_global_function_manager(gcs_address)
    @info "Connecting function manager to GCS at $gcs_address..."
    gcs_client = ray_jll.JuliaGcsClient(gcs_address)
    status = ray_jll.Connect(gcs_client)
    ray_jll.ok(status) || error("Could not connect to GCS")
    FUNCTION_MANAGER[] = FunctionManager(; gcs_client, functions=Dict{String,Any}())
    return nothing
end

function function_key(fd::ray_jll.JuliaFunctionDescriptor, job_id=get_job_id())
    return string("RemoteFunction:", job_id, ":", fd.function_hash)
end

function export_function!(fm::FunctionManager, f, job_id=get_job_id())
    fd = ray_jll.function_descriptor(f)
    function_locations = functionloc.(methods(f))
    key = function_key(fd, job_id)
    @debug "Exporting function to function store:" fd key function_locations
    # DFK: I _think_ the string memory may be mangled if we don't `deepcopy`. Not sure but
    # it can't hurt
    if ray_jll.Exists(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE, deepcopy(key))
        @debug "Function already present in GCS store:" fd key
    else
        @debug "Exporting function to GCS store:" fd key
        val = base64encode(serialize, f)
        check_oversized_function(val, fd)
        ray_jll.Put(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE, key, val, true)
    end
end

# XXX: this will error if the function is not found in the store.
# TODO: consider _trying_ to resolve the function descriptor locally (i.e.,
# somthing like `eval(Meta.parse(CallString(fd)))`), falling back to the function
# store only if needed.
# https://github.com/beacon-biosignals/Ray.jl/issues/60
function import_function!(fm::FunctionManager, fd::ray_jll.JuliaFunctionDescriptor,
                          job_id=get_job_id())
    return get!(fm.functions, fd.function_hash) do
        key = function_key(fd, job_id)
        @debug "Function not found locally, retrieving from function store" fd key
        val = ray_jll.Get(fm.gcs_client, FUNCTION_MANAGER_NAMESPACE, key)
        try
            io = IOBuffer()
            iob64 = Base64DecodePipe(io)
            write(io, val)
            seekstart(io)
            f = deserialize(iob64)
            # need to handle world-age issues on remote workers when
            # deserializing the function effectively defines it
            return (args...; kwargs...) -> Base.invokelatest(f, args...; kwargs...)
        catch e
            error("Failed to deserialize function from store: $(fd)")
        end
    end
end
