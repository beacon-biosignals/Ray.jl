# The design of `flatten_args` and `recover_args` is heavily based upon the Python Ray
# client which uses a similar approach
# (https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_private/signature.py#L81).
# One area of concern is that the flattening occurs before Ray task arguments are determined
# if they should be passed by value or by reference
# (https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/_raylet.pyx#L695) which may
# be problematic as you would only want to add the values to the object store and not the
# associated keyword.

# TODO: Currently we are completely ignoring cross language support
# https://github.com/ray-project/ray/blob/ray-2.5.1/python/ray/remote_function.py#L379

# Underscores are not allowed to be used as Julia function keywords
# https://docs.julialang.org/en/v1/manual/variables/#man-allowed-variable-names
const ARG_KEY = :_

function flatten_args(args, kwargs)
    flattened = Pair{Symbol,Any}[]
    sizehint!(flattened, length(args) + length(kwargs))

    for arg in args
        push!(flattened, ARG_KEY => arg)
    end

    for kwarg in pairs(kwargs)
        push!(flattened, kwarg)
    end

    return flattened
end

function recover_args(flattened)
    args = []
    kwargs = Pair{Symbol,Any}[]

    for pair in flattened
        k, v = pair
        if k === ARG_KEY
            push!(args, v)
        else
            push!(kwargs, pair)
        end
    end

    return args, kwargs
end
