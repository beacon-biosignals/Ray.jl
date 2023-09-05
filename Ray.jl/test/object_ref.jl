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
end
