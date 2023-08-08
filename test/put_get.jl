using ray_core_worker_julia_jll: put, get

@testset "put / get" begin
    @testset "roundtrip vector" begin
        data = UInt16[1:3;]
        obj_ref = put(LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true))

        # TODO: Currently uses size/length from `data`
        buffer = get(obj_ref)
        buffer_ptr = Ptr{UInt8}(Data(buffer[]).cpp_object)
        buffer_size = Size(buffer[])
        T = eltype(data)
        len = buffer_size ÷ sizeof(T)
        result = Vector{T}(undef, len)
        unsafe_copyto!(Ptr{UInt8}(pointer(result)), buffer_ptr, buffer_size)
        @test typeof(result) == typeof(data)
        @test result == data
        @test result !== data
    end

    @testset "roundtrip string" begin
        data = "Greetings from Julia!"
        obj_ref = put(LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true))

        buffer = get(obj_ref)
        buffer_ptr = Ptr{UInt8}(Data(buffer[]).cpp_object)
        buffer_size = Size(buffer[])
        v = Vector{UInt8}(undef, buffer_size)
        unsafe_copyto!(Ptr{UInt8}(pointer(v)), buffer_ptr, buffer_size)
        result = String(v)
        @test typeof(result) == typeof(data)
        @test result == data
    end
end
