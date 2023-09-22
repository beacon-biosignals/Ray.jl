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

    @testset "Local ref count: put, deepcopy, and constructed object ref" begin
        obj = Ray.put(nothing)
        oid = obj.oid_hex

        @test local_count(obj) == 1

        obj2 = deepcopy(obj)
        @test local_count(obj) == 2

        finalize(obj2)
        yield()  # allows async task that makes the API call to run

        @test local_count(obj) == 1

        obj3 = ObjectRef(obj.oid_hex)
        @test local_count(obj) == 2

        finalize(obj3)
        yield()
        @test local_count(obj) == 1

        finalize(obj)
        yield()
        @test local_count(oid) == 0
    end
end
