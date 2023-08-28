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
