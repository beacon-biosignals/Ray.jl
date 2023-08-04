@testset "put / get" begin
    @testset "roundtrip string" begin
        obj_ref1 = put("Greetings from Julia!")
        @test get(obj_ref1) == "Greetings from Julia!"
    end
end
