using .ray_julia_jll: LocalMemoryBuffer, Data
using .ray_julia_jll: RayObject, GetData
using .ray_julia_jll: ObjectID
using .ray_julia_jll: ok

@testset "put / get / contains" begin
    @testset "contains" begin
        oid = ray_julia_jll.FromRandom(ObjectID)
        @test !ray_julia_jll.contains(oid)
    end

    @testset "roundtrip vector" begin
        data = UInt16[1:3;]
        buffer = LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true)
        oid = CxxPtr(ray_jll.ObjectID())
        status = ray_julia_jll.put(RayObject(buffer), StdVector{ObjectID}(), oid)
        @test ok(status)
        @test ray_julia_jll.contains(oid[])

        # TODO: Currently uses size/length from `data`
        # https://github.com/beacon-biosignals/Ray.jl/issues/55
        ray_obj = CxxPtr(SharedPtr{ray_jll.RayObject}())
        status = ray_julia_jll.get(oid[], -1, ray_obj)
        @test ok(status)
        buffer = GetData(ray_obj[][])
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
        oid = CxxPtr(ray_jll.ObjectID())
        status = ray_julia_jll.put(RayObject(buffer), StdVector{ObjectID}(), oid)
        @test ok(status)
        @test ray_julia_jll.contains(oid[])

        ray_obj = CxxPtr(SharedPtr{ray_jll.RayObject}())
        status = ray_julia_jll.get(oid[], -1, ray_obj)
        @test ok(status)
        buffer = GetData(ray_obj[][])
        buffer_ptr = Ptr{UInt8}(Data(buffer[]).cpp_object)
        buffer_size = Size(buffer[])
        v = Vector{UInt8}(undef, buffer_size)
        unsafe_copyto!(Ptr{UInt8}(pointer(v)), buffer_ptr, buffer_size)
        result = String(v)
        @test typeof(result) == typeof(data)
        @test result == data
    end
end
