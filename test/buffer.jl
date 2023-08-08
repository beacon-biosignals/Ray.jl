using Serialization: deserialize, serialize
using Test
using ray_core_worker_julia_jll: LocalMemoryBuffer, Data, Size, OwnsData, IsPlasmaBuffer

@testset "LocalMemoryBuffer" begin
    data = UInt16[1:3;]

    @testset "non-copied object reference" begin
        buffer = LocalMemoryBuffer(pointer_from_objref(data), sizeof(data), false)
        b = buffer[][]
        @test Data(b) == pointer_from_objref(data)
        @test Size(b) == sizeof(data)
        @test !OwnsData(b)
        @test !IsPlasmaBuffer(b)

        result = unsafe_pointer_to_objref(Data(b).cpp_object)
        @test typeof(result) == typeof(data)
        @test result === data
    end

    # TODO: Using `sizeof` is probably wrong for `pointer_from_objref` as there is probably
    # additional Julia type metadata not being accounted for. This may be why we see a
    # segfault when trying to use `pointer_from_objref`.
    @testset "copied object reference" begin
        buffer = LocalMemoryBuffer(pointer_from_objref(data), sizeof(data), true)
        b = buffer[][]
        @test Data(b) != pointer_from_objref(data)
        @test Size(b) == sizeof(data)
        @test OwnsData(b)
        @test !IsPlasmaBuffer(b)

        # Attempting to use `unsafe_pointer_to_objref(Data(buffer).cpp_object)` would result in a
        # segfault.
    end

    @testset "copied data pointer" begin
        buffer = LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true)
        b = buffer[][]
        @test Data(b) != pointer(data)
        @test Size(b) == sizeof(data)
        @test OwnsData(b)
        @test !IsPlasmaBuffer(b)

        T = eltype(data)
        len = Size(b) ÷ sizeof(T)
        result = Vector{T}(undef, len)
        unsafe_copyto!(Ptr{UInt8}(pointer(result)), Data(b).cpp_object, Size(b))
        @test typeof(result) == typeof(data)
        @test result == data
        @test result !== data
    end

    @testset "copied serialized object" begin
        serialized = Vector{UInt8}(sprint(serialize, data))
        buffer = LocalMemoryBuffer(serialized, sizeof(serialized), true)
        b = buffer[][]
        @test Size(b) == sizeof(serialized)
        @test OwnsData(b)
        @test !IsPlasmaBuffer(b)

        v = Vector{UInt8}(undef, Size(b))
        unsafe_copyto!(pointer(v), Data(b).cpp_object, Size(b))
        result = deserialize(IOBuffer(v))
        @test typeof(result) == typeof(data)
        @test result == data
        @test result !== data
    end
end
