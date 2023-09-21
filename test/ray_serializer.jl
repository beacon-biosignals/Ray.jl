@testset "RaySerializer" begin
    @testset "byte constructor" begin
        bytes = Vector{UInt8}()
        s = Ray.RaySerializer(bytes)
        @test isempty(bytes)

        serialize(s, 1)
        @test !isempty(bytes)
    end

    @testset "object_ids property" begin
        s = Ray.RaySerializer(IOBuffer())
        @test s.object_ids isa Set{ray_jll.ObjectIDAllocated}
    end

    # Note: Serializing `ObjectRef` requires the core worker to be initialized
    @testset "inlined object refs" begin
        oids = [ray_jll.FromRandom(ray_jll.ObjectID) for _ in 1:3]
        obj_refs = map(ObjectRef, oids)
        x = [1, 2, obj_refs...]

        s = Ray.RaySerializer(IOBuffer())
        serialize(s, x)

        @test s.object_refs isa Set{ObjectRef}
        @test s.object_refs == Set(obj_refs)
        @test s.object_ids isa Set{ray_jll.ObjectIDAllocated}
        @test s.object_ids == Set(oids)
    end

    # Note: Serializing `ObjectRef` requires the core worker to be initialized
    @testset "reset_state" begin
        obj_ref = ObjectRef(ray_jll.FromRandom(ray_jll.ObjectID))
        s = Ray.RaySerializer(IOBuffer())
        serialize(s, obj_ref)
        @test !isempty(s.object_refs)

        Serialization.reset_state(s)
        @test isempty(s.object_refs)
    end

    @testset "header support" begin
        bytes = Vector{UInt8}()
        s = Ray.RaySerializer(IOBuffer(bytes; write=true))
        Serialization.writeheader(s)

        s = Ray.RaySerializer(IOBuffer(bytes))
        b = Int32(read(s.io, UInt8)::UInt8)
        @test b == Serialization.HEADER_TAG

        # Using `readheader` requires the serializer to have the `version` field
        @test Serialization.readheader(s) === nothing
    end
end

@testset "serialize_to_bytes / deserialize_from_bytes" begin
    @testset "roundtrip" begin
        x = [1, 2, 3]
        bytes = Ray.serialize_to_bytes(x)
        @test bytes isa Vector{UInt8}
        @test !isempty(bytes)

        result = Ray.deserialize_from_bytes(bytes)
        @test typeof(result) == typeof(x)
        @test result == x
    end

    # TODO: Investigate if want to include the serialization header
    @testset "serialize with header" begin
        x = 123
        bytes = Ray.serialize_to_bytes(x)

        s = Serializer(IOBuffer(bytes))
        b = Int32(read(s.io, UInt8)::UInt8)
        @test b == Serialization.HEADER_TAG
        Serialization.readheader(s)  # Throws if header not present
        @test deserialize(s) == x
    end
end

@testset "serialize_to_ray_object" begin
    @testset "nested object ids" begin
        obj1 = Ray.put(1)
        obj2 = Ray.put(2)

        objs = [obj1, obj2]
        ray_obj = Ray.serialize_to_ray_object(objs)
        nested_obj_ids = ray_jll.GetNestedRefIds(ray_obj[])

        @test issetequal([o.oid for o in objs], nested_obj_ids)

        ray_obj2 = Ray.serialize_to_ray_object([obj1, (obj2, obj1, "blah"), 1])
        nested_obj_ids2 = ray_jll.GetNestedRefIds(ray_obj2[])
        @test length(nested_obj_ids2) == 2
        @test issetequal(nested_obj_ids2, nested_obj_ids)
    end
end
