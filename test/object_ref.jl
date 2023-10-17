# this runs inside setup_core_worker()

function serialize_deserialize(x)
    io = IOBuffer()
    serialize(io, x)
    seekstart(io)
    return deserialize(io)
end

@testset "safe_convert" begin
    expected = "¿\0ÿ"
    cpp_expected = "Â¿\0Ã¿"

    std_str = Ray.safe_convert(StdString, expected)
    @test length(std_str) == length(cpp_expected)
    @test collect(std_str) == collect(cpp_expected)
    @test ncodeunits(std_str) == ncodeunits(expected)
    @test codeunits(std_str) == codeunits(expected)

    str = Ray.safe_convert(String, std_str)
    @test length(str) == length(expected)
    @test collect(str) == collect(expected)
    @test ncodeunits(str) == ncodeunits(expected)
    @test codeunits(str) == codeunits(expected)
end

@testset "ObjectRef" begin
    @testset "basic" begin
        hex_str = "f"^(2 * 28)
        obj_ref = ObjectRef(hex_str)
        @test Ray.hex_identifier(obj_ref) == hex_str
        @test obj_ref.oid == ray_jll.FromHex(ray_jll.ObjectID, hex_str)
        @test obj_ref.owner_address == ray_jll.Address()
        @test obj_ref == ObjectRef(hex_str)
        @test hash(obj_ref) == hash(ObjectRef(hex_str))
    end

    @testset "no owner address constructors" begin
        hex_str = "f"^(2 * 28)
        @test ObjectRef(hex_str, "", "").owner_address == ray_jll.Address()
        @test ObjectRef(hex_str, "{}", "").owner_address == ray_jll.Address()
    end

    @testset "show" begin
        hex_str = "f"^(2 * 28)
        obj_ref = ObjectRef(hex_str)
        @test sprint(show, obj_ref) == "ObjectRef(\"$hex_str\")"
    end

    # Note: Serializing `ObjectRef` requires the core worker to be initialized
    @testset "serialize/deserialize" begin
        obj_ref1 = ObjectRef(ray_jll.FromRandom(ray_jll.ObjectID))
        obj_ref2 = serialize_deserialize(obj_ref1)
        @test obj_ref1 == obj_ref2
    end
end
