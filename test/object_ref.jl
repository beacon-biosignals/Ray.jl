# this runs inside setup_core_worker()

function serialize_deserialize(x)
    io = IOBuffer()
    serialize(io, x)
    seekstart(io)
    return deserialize(io)
end

@testset "ObjectRef" begin
    @testset "basic" begin
        hex_str = "f" ^ (2 * 28)
        obj_ref = ObjectRef(hex_str)
        @test Ray.hex_identifier(obj_ref) == hex_str
        @test obj_ref.oid == ray_jll.FromHex(ray_jll.ObjectID, hex_str)
        @test obj_ref.owner_address === nothing
        @test obj_ref == ObjectRef(hex_str)
        @test hash(obj_ref) == hash(ObjectRef(hex_str))

        # test various "no owner address" constructors
        @test ObjectRef(hex_str, nothing, "") == obj_ref
        @test ObjectRef(hex_str, "", "") == obj_ref
    end

    @testset "show" begin
        hex_str = "f" ^ (2 * 28)
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
