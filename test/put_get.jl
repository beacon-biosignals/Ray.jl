using ray_core_worker_julia_jll: put, get

@testset "put / get" begin
    @testset "roundtrip vector" begin
        data = UInt16[1:3;]
        obj_ref = put(LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true))

        # TODO: Currently uses size/length from `data`
        buffer = get(obj_ref)
        b = buffer[][]
        T = eltype(data)
        len = Size(b) ÷ sizeof(T)
        result = Vector{T}(undef, len)
        unsafe_copyto!(Ptr{UInt8}(pointer(result)), Ptr{UInt8}(Data(b).cpp_object), Size(b))
        @test typeof(result) == typeof(data)
        @test result == data
        @test result !== data
    end

    @testset "roundtrip string" begin
        data = "Greetings from Julia!"
        obj_ref = put(LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true))

        buffer = get(obj_ref)
        b = buffer[][]
        v = Vector{UInt8}(undef, Size(b))
        unsafe_copyto!(Ptr{UInt8}(pointer(v)), Ptr{UInt8}(Data(b).cpp_object), Size(b))
        result = String(v)
        @test typeof(result) == typeof(data)
        @test result == data
    end
end
