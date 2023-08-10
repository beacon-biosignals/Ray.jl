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

# function manager holds:
# local cache of functions (keyed by function id/hash from descriptor)
# gcs client
#
#

using ray_core_worker_julia_jll: JuliaGcsClient

# TODO: remove indirection after fields are settled
Base.@kwdef struct FunctionManager1
    gcs_client::JuliaGcsClient
    functions::Dict
end

# TODO: remove indirection after fields are settled
FunctionManager = FunctionManager1

function_key(fn) = 

export_function(fm::FunctionManager, 

# function manager operations:
# export function (check gcs for key, serialize and put if needed)
# import function (check local store; query gcs if needed, deserialize, add to local store)

