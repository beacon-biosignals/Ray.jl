using ray_core_worker_julia_jll: put, get
using ray_core_worker_julia_jll: LocalMemoryBuffer, Data
using ray_core_worker_julia_jll: RayObject, GetData
using ray_core_worker_julia_jll: ObjectID

@testset "put / get" begin
    @testset "roundtrip vector" begin
        data = UInt16[1:3;]
        buffer = LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true)
        oid = ObjectID()
        put(RayObject(buffer), StdVector{ObjectID}(), CxxPtr(oid))

        # TODO: Currently uses size/length from `data`
        # https://github.com/beacon-biosignals/ray_core_worker_julia_jll.jl/issues/55
        ray_obj = get(oid)
        buffer = GetData(ray_obj[])
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
        buffer = LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true)
        oid = ObjectID()
        put(RayObject(buffer), StdVector{ObjectID}(), CxxPtr(oid))

        ray_obj = get(oid)
        buffer = GetData(ray_obj[])
        buffer_ptr = Ptr{UInt8}(Data(buffer[]).cpp_object)
        buffer_size = Size(buffer[])
        v = Vector{UInt8}(undef, buffer_size)
        unsafe_copyto!(Ptr{UInt8}(pointer(v)), buffer_ptr, buffer_size)
        result = String(v)
        @test typeof(result) == typeof(data)
        @test result == data
    end
end
