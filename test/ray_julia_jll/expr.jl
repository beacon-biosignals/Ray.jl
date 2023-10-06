const FRUIT_SYMBOLS = (:APPLE, :ORANGE, :KIWI)

@testset "_enum_symbol_constructor_expr" begin
    expected = quote
        function Fruit(member::Symbol)
            return if member === :APPLE
                APPLE
            elseif member === :ORANGE
                ORANGE
            elseif member === :KIWI
                KIWI
            else
                throw(ArgumentError("$(Fruit) has no member named: $(member)"))
            end
        end
    end
    Base.remove_linenums!(expected)

    expr = ray_julia_jll._enum_symbol_constructor_expr(:Fruit, FRUIT_SYMBOLS)
    Base.remove_linenums!(expr)
    @test expr isa Expr
    @test expr == expected
end

@testset "_enum_symbol_accessor_expr" begin
    expected = quote
        function Base.Symbol(member::Fruit)
            return if member === APPLE
                :APPLE
            elseif member === ORANGE
                :ORANGE
            elseif member === KIWI
                :KIWI
            else
                throw(ArgumentError("$(Fruit) has no member named: $(member)"))
            end
        end
    end
    Base.remove_linenums!(expected)

    expr = ray_julia_jll._enum_symbol_accessor_expr(:Fruit, FRUIT_SYMBOLS)
    Base.remove_linenums!(expr)
    @test expr isa Expr
    @test expr == expected
end

@testset "_enum_instances_expr" begin
    expected = quote
        function Base.instances(::Type{Fruit})
            return (APPLE, ORANGE, KIWI)
        end
    end
    Base.remove_linenums!(expected)

    expr = ray_julia_jll._enum_instances_expr(:Fruit, FRUIT_SYMBOLS)
    Base.remove_linenums!(expr)
    @test expr isa Expr
    @test expr == expected
end

@testset "_enum_expr" begin
    expected = quote
        $(ray_julia_jll._enum_symbol_constructor_expr(:Fruit, FRUIT_SYMBOLS))
        $(ray_julia_jll._enum_symbol_accessor_expr(:Fruit, FRUIT_SYMBOLS))
        $(ray_julia_jll._enum_instances_expr(:Fruit, FRUIT_SYMBOLS))
    end
    Base.remove_linenums!(expected)

    expr = ray_julia_jll._enum_expr(:Fruit, FRUIT_SYMBOLS)
    Base.remove_linenums!(expr)
    @test expr isa Expr
    @test expr == expected
end
