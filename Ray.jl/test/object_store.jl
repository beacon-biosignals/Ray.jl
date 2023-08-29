function serialize_deserialize(x)
    io = IOBuffer()
    serialize(io, x)
    seekstart(io)
    return deserialize(io)
end

@testset "object_store.jl" begin

    @testset "Put/Get roundtrip for $(typeof(x))" for x in (
        1, 1.23, "hello", (1, 2, 3), [1, 2, 3],
    )
        oid = Ray.put(x)
        @test Ray.get(oid) == x
    end

    @testset "get same object twice" begin
        oid = Ray.put(1)
        @test Ray.get(oid) == 1
        @test Ray.get(oid) == 1
    end

    @testset "get collections of objects" begin
        oid1 = Ray.put(123)
        oid2 = Ray.put("hello")
        @test Ray.get.([oid2, oid1]) == ["hello", 123]
    end

    @testset "get fallback" begin
        @test Ray.get(123) == 123
    end

    @testset "serialize object" begin
        oid1 = Ray.put(123)
        oid2 = serialize_deserialize(oid1)
        @test oid1 != oid2
        @test Ray.get(oid1) == Ray.get(oid2)
    end
end
