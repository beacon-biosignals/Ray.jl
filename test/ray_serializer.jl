@testset "RaySerializer" begin
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
