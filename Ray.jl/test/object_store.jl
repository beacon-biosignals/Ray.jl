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
end
