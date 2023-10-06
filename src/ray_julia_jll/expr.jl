function _enum_symbol_constructor_expr(enum::Symbol, members)
    block = Expr(:block, members[1])
    body = Expr(:if, :(member === $(QuoteNode(members[1]))), block, nothing)
    ex = body
    for member in members[2:end]
        cond = Expr(:block, :(member === $(QuoteNode(member))))
        block = Expr(:block, member)
        ex.args[3] = Expr(:elseif, cond, block, nothing)
        ex = ex.args[3]
    end
    exception = :(ArgumentError("$($enum) has no member named: $member"))
    ex.args[3] = Expr(:block, :(throw($exception)))

    return quote
        function $enum(member::Symbol)
            return $body
        end
    end
end

function _enum_symbol_accessor_expr(enum::Symbol, members)
    block = Expr(:block, QuoteNode(members[1]))
    body = Expr(:if, :(member === $(members[1])), block, nothing)
    ex = body
    for member in members[2:end]
        cond = Expr(:block, :(member === $member))
        block = Expr(:block, QuoteNode(member))
        ex.args[3] = Expr(:elseif, cond, block, nothing)
        ex = ex.args[3]
    end
    exception = :(ArgumentError("$($enum) has no member named: $member"))
    ex.args[3] = Expr(:block, :(throw($exception)))

    members_tuple = Expr(:tuple, members...)

    return quote
        function Base.Symbol(member::$enum)
            return $body
        end
    end
end

function _enum_instances_expr(enum::Symbol, members)
    members_tuple = Expr(:tuple, members...)

    return quote
        function Base.instances(::Type{$enum})
            return $members_tuple
        end
    end
end

function _enum_expr(enum::Symbol, members)
    return quote
        $(_enum_symbol_constructor_expr(enum, members))
        $(_enum_symbol_accessor_expr(enum, members))
        $(_enum_instances_expr(enum, members))
    end
end
