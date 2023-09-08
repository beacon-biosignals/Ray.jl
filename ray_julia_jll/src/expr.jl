function _enum_getproperty_expr(base_type::Type, members)
    body = Expr(:if, :(field === $(QuoteNode(members[1]))), members[1], nothing)
    ex = body
    for member in members[2:end]
        ex.args[3] = Expr(:elseif, :(field === $(QuoteNode(member))), member, nothing)
        ex = ex.args[3]
    end
    ex.args[3] = :(Base.getfield($(nameof(base_type)), field))

    return quote
        function Base.getproperty(::Type{$(nameof(base_type))}, field::Symbol)
            $body
        end
    end
end

function _enum_propertynames_expr(base_type::Type, members)
    public_properties = Expr(:tuple, QuoteNode.(members)...)
    private_properties = Expr(:tuple,
                              QuoteNode.(members)...,
                              QuoteNode.(fieldnames(typeof(base_type)))...)

    return quote
        function Base.propertynames(::Type{$(nameof(base_type))}, private::Bool=false)
            if private
                $private_properties
            else
                $public_properties
            end
        end
    end
end

# function Base.Symbol(language::Language)
#     return if language === PYTHON
#         :PYTHON
#     elseif field === JAVA
#         :JAVA
#     elseif field === CPP
#         :CPP
#     elseif field === JULIA
#         :JULIA
#     else
#         throw(ArgumentError("Unknown language: $language"))
#     end
# end

# Base.instances(::Type{Language}) = (PYTHON, JAVA, CPP, JULIA)
