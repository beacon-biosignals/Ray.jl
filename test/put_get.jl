@testset "put / get" begin
    @testset "roundtrip vector" begin
        data = UInt16[1:3;]
        obj_ref = put(Ptr{Nothing}(pointer(data)), sizeof(data))
        ptr = get(obj_ref)
        result = Vector{UInt16}(undef, length(data))
        unsafe_copyto!(Ptr{Nothing}(pointer(result)), ptr, sizeof(data))
    end

    #=
    @testset "roundtrip string" begin
        obj_ref1 = put("Greetings from Julia!")
        @test get(obj_ref1) == "Greetings from Julia!"
    end
    =#
end
