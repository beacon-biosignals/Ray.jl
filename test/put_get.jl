using ray_core_worker_julia_jll: put, get

@testset "put / get" begin
    @testset "roundtrip vector" begin
        data = UInt16[1:3;]
        obj_ref = put(Ptr{Nothing}(pointer(data)), sizeof(data))

        # TODO: Currently uses size/length from `data`
        buffer = get(obj_ref)[][]
        T = eltype(data)
        len = sizeof(buffer) ÷ sizeof(T)
        result = Vector{T}(undef, len)
        unsafe_copyto!(Ptr{UInt8}(pointer(result)), Ptr{UInt8}(data_pointer(buffer)), sizeof(buffer))
        @test typeof(result) == typeof(data)
        @test result == data
        @test result !== data
    end

    @testset "roundtrip string" begin
        data = "Greetings from Julia!"
        obj_ref = put(Ptr{Nothing}(pointer(data)), sizeof(data))

        buffer = get(obj_ref)[][]
        v = Vector{UInt8}(undef, sizeof(buffer))
        unsafe_copyto!(Ptr{UInt8}(pointer(v)), Ptr{UInt8}(data_pointer(buffer)), sizeof(buffer))
        result = String(v)
        @test typeof(result) == typeof(data)
        @test result == data
    end
end
