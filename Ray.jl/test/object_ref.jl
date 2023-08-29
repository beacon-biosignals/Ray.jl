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
        @test obj_ref == ObjectRef(hex_str)
        @test string(obj_ref) == hex_str
    end

    @testset "show" begin
        hex_str = "f" ^ (2 * 28)
        obj_ref = ObjectRef(hex_str)
        @test sprint(show, obj_ref) == "ObjectRef(\"$hex_str\")"
    end

    @testset "serialize/deserialize" begin
        obj_ref1 = ObjectRef(ray_jll.FromRandomObjectID())
        obj_ref2 = serialize_deserialize(obj_ref1)
        @test obj_ref1 == obj_ref2
    end
end
