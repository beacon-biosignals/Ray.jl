struct Fruit
    val::UInt8
end

const APPLE = Fruit(0x01)
const ORANGE = Fruit(0x02)
const KIWI = Fruit(0x03)

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

    @testset "evaluated" begin
        eval(expr)
        @test Fruit(:APPLE) == APPLE
        @test_throws ArgumentError Fruit(:UNKNOWN)
    end
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

    @testset "evaluated" begin
        eval(expr)
        @test Symbol(APPLE) == :APPLE
        @test_throws ArgumentError Symbol(Fruit(typemax(UInt8)))
    end
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

    @testset "evaluated" begin
        eval(expr)
        @test instances(Fruit) == (APPLE, ORANGE, KIWI)
    end
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
