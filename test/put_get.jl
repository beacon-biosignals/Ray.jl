using ray_core_worker_julia_jll: put, get

@testset "put / get" begin
    @testset "roundtrip vector" begin
        worker = ray_jll.GetCoreWorker()

        data = UInt16[1:3;]
        buffer = LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true)
        obj_ref = put(worker, buffer)

        # TODO: Currently uses size/length from `data`
        # https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl/issues/55
        buffer = get(worker, obj_ref)
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
        worker = ray_jll.GetCoreWorker()

        data = "Greetings from Julia!"
        buffer = LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true)
        obj_ref = put(worker, buffer)

        buffer = get(worker, obj_ref)
        buffer_ptr = Ptr{UInt8}(Data(buffer[]).cpp_object)
        buffer_size = Size(buffer[])
        v = Vector{UInt8}(undef, buffer_size)
        unsafe_copyto!(Ptr{UInt8}(pointer(v)), buffer_ptr, buffer_size)
        result = String(v)
        @test typeof(result) == typeof(data)
        @test result == data
    end
end
