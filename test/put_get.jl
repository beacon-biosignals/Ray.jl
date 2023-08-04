using ray_core_worker_julia_jll: put, get

@testset "put / get" begin
    @testset "roundtrip vector" begin
        data = UInt16[1:3;]
        obj_ref = put(Ptr{Nothing}(pointer(data)), sizeof(data))

        # TODO: Currently uses size/length from `data`
        ptr = get(obj_ref)
        result = Vector{UInt16}(undef, length(data))
        unsafe_copyto!(Ptr{UInt8}(pointer(result)), Ptr{UInt8}(ptr), sizeof(data))
        @test typeof(result) == typeof(data)
        @test result == data
        @test result !== data
    end

    @testset "roundtrip string" begin
        data = "Greetings from Julia!"
        obj_ref = put(Ptr{Nothing}(pointer(data)), sizeof(data))

        ptr = get(obj_ref)
        v = Vector{UInt8}(undef, sizeof(data))
        unsafe_copyto!(Ptr{UInt8}(pointer(v)), Ptr{UInt8}(ptr), sizeof(data))
        result = String(v)
        @test typeof(result) == typeof(data)
        @test result == data
    end
end
