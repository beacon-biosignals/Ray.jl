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

@testset "serialize_to_ray_object / deserialize_from_ray_object" begin
    @testset "invalid data" begin
        # Only serializing the header will fail upon deserialization
        data = Vector{UInt8}()
        s = Ray.RaySerializer(IOBuffer(data; write=true))
        Serialization.writeheader(s)

        data_buf = ray_jll.LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data),
                                             true)
        metadata_buf = ray_jll.NullPtr(ray_jll.Buffer)
        nested_refs = StdVector{ray_jll.ObjectReference}()
        ray_obj = RayObject(data_buf, metadata_buf, nested_refs, false)

        msg = "Unable to deserialize bytes: $(bytes2hex(data))"
        @test_logs (:error, msg) begin
            @test_throws EOFError Ray.deserialize_from_ray_object(ray_obj)
        end

        obj_ref = ObjectRef(ray_jll.FromRandom(ray_jll.ObjectID))
        msg = "Unable to deserialize `$(repr(obj_ref))` bytes: $(bytes2hex(data))"
        @test_logs (:error, msg) begin
            @test_throws EOFError Ray.deserialize_from_ray_object(ray_obj, obj_ref)
        end
    end

    @testset "metadata handling" begin
        data = [1, 2, 3]
        data_buf = ray_jll.GetData(Ray.serialize_to_ray_object(data)[])

        metadata = b"hello\x00world"
        metadata_buf = ray_jll.LocalMemoryBuffer(Ptr{Nothing}(pointer(metadata)), sizeof(metadata), true)

        nested_refs = StdVector{ray_jll.ObjectReference}()
        ray_obj = ray_jll.RayObject(data_buf, metadata_buf, nested_refs, false)
        @test take!(ray_jll.GetMetadata(ray_obj[])[]) == metadata

        @test_throws "Encountered unhandled metadata: hello\x00world" begin
            Ray.deserialize_from_ray_object(ray_obj)
        end
    end
end
