function _enum_symbol_constructor_expr(base_type::Type, members)
    base_type_sym = nameof(base_type)
    body = Expr(:if, :(member === $(QuoteNode(members[1]))), members[1], nothing)
    ex = body
    for member in members[2:end]
        ex.args[3] = Expr(:elseif, :(member === $(QuoteNode(member))), member, nothing)
        ex = ex.args[3]
    end
    ex.args[3] = :(throw(ArgumentError("$($base_type_sym) has no member named: $member")))

    return quote
        function $base_type_sym(member::Symbol)
            return $body
        end
    end
end

function _enum_symbol_accessor_expr(base_type::Type, members)
    base_type_sym = nameof(base_type)
    body = Expr(:if, :(member === $(members[1])), QuoteNode(members[1]), nothing)
    ex = body
    for member in members[2:end]
        ex.args[3] = Expr(:elseif, :(member === $member), QuoteNode(member), nothing)
        ex = ex.args[3]
    end
    ex.args[3] = :(throw(ArgumentError("$($base_type_sym) has no member named: $member")))

    base_type_sym = nameof(base_type)
    members_tuple = Expr(:tuple, members...)

    return quote
        function Base.Symbol(member::$base_type)
            return $body
        end
    end
end

function _enum_instances_expr(base_type::Type, members)
    base_type_sym = nameof(base_type)
    members_tuple = Expr(:tuple, members...)

    return quote
        function Base.instances(::Type{$base_type})
            return $members_tuple
        end
    end
end

function _enum_expr(base_type::Type, members)
    return quote
        $(_enum_symbol_constructor_expr(base_type, members))
        $(_enum_symbol_accessor_expr(base_type, members))
        $(_enum_instances_expr(base_type, members))
    end
end
