@testset "object_store.jl" begin
    @testset "Put/Get roundtrip for $(typeof(x))" for x in (
        1, 1.23, "hello", (1, 2, 3), [1, 2, 3],
    )
        obj_ref = Ray.put(x)
        @test obj_ref isa ObjectRef
        @test Ray.get(obj_ref) == x
    end

    @testset "get same object twice" begin
        obj_ref = Ray.put(1)
        @test Ray.get(obj_ref) == 1
        @test Ray.get(obj_ref) == 1
    end

    @testset "get collections of objects" begin
        obj_ref1 = Ray.put(123)
        obj_ref2 = Ray.put("hello")
        @test Ray.get.([obj_ref2, obj_ref1]) == ["hello", 123]
    end

    @testset "get fallback" begin
        @test Ray.get(123) == 123
    end

    @testset "put object reference" begin
        obj_ref1 = Ray.put(123)
        obj_ref2 = Ray.put(obj_ref1)
        @test obj_ref1 === obj_ref2
        @test Ray.get(obj_ref1) == Ray.get(obj_ref2)
    end
end
