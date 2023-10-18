@testset "object_store.jl" begin
    @testset "Put/Get roundtrip for $(typeof(x))" for x in (1, 1.23, "hello", (1, 2, 3),
                                                            [1, 2, 3])
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

    @testset "Object owner" begin
        obj = Ray.put(1)
        # ownership only embedded in ObjectRef on serialization
        result = Ray.deserialize_from_ray_object(Ray.serialize_to_ray_object(obj))
        @test result.owner_address == Ray.get_owner_address(obj)
    end

    @testset "deepcopy object reference owner address" begin
        obj1 = Ray.put(42)
        addr = Ray.get_owner_address(obj1)
        obj2 = ObjectRef(Ray.hex_identifier(obj1), addr, "")
        obj3 = deepcopy(obj2)

        @test obj1.owner_address != addr  # Usually only populated upon deserialization
        @test obj2.owner_address == addr
        @test obj3.owner_address == addr

        finalize(obj2)
        yield()

        # Avoid comparing against `addr` here as the finalizer could modify it in place
        # allowing this test to pass.
        @test obj3.owner_address == Ray.get_owner_address(obj1)
    end
end

@testset "serialize_to_ray_object" begin
    # these tests use Ray.put so they're here instead of `ray_serializer.jl`
    @testset "nested objects" begin
        obj1 = Ray.put(1)
        obj2 = Ray.put(2)

        objs = [obj1, obj2]
        ray_obj = Ray.serialize_to_ray_object(objs)
        nested_obj_ids = ray_jll.GetNestedRefIds(ray_obj[])

        @test issetequal([o.oid for o in objs], nested_obj_ids)
        @test Ray.deserialize_from_ray_object(ray_obj) == objs

        stuff2 = [obj1, (obj2, obj1, "blah"), 1]
        ray_obj2 = Ray.serialize_to_ray_object(stuff2)
        nested_obj_ids2 = ray_jll.GetNestedRefIds(ray_obj2[])
        @test length(nested_obj_ids2) == 2
        @test issetequal(nested_obj_ids2, nested_obj_ids)

        @test Ray.deserialize_from_ray_object(ray_obj2) == stuff2
    end
end
