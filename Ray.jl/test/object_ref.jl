@testset "ObjectRef" begin
    @testset "basic" begin
        hex_str = "f" ^ (2 * 28)
        obj_ref = ObjectRef(hex_str)
        @test obj_ref == ObjectRef(hex_str)
        @test hex_identifier(obj_ref) == hex_str
    end

    @testset "show" begin
        hex_str = "f" ^ (2 * 28)
        obj_ref = ObjectRef(hex_str)
        @test sprint(show, obj_ref) == "ObjectRef(\"$hex_str\")"
    end

    @testset "convert" begin
        oid = ray_jll.FromRandom(ray_jll.ObjectID)
        obj_ref = ObjectRef(oid)
        @test convert(ray_jll.ObjectID, obj_ref) === oid
    end
end
