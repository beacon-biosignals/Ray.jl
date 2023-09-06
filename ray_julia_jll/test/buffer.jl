using Serialization: deserialize, serialize
using Test
using ray_julia_jll: LocalMemoryBuffer, Data, Size, OwnsData, IsPlasmaBuffer

@testset "LocalMemoryBuffer" begin
    data = UInt16[1:3;]

    @testset "non-copied object reference" begin
        buffer = LocalMemoryBuffer(pointer_from_objref(data), sizeof(data), false)
        @test Data(buffer[]) == pointer_from_objref(data)
        @test Size(buffer[]) == sizeof(data)
        @test !OwnsData(buffer[])
        @test !IsPlasmaBuffer(buffer[])

        buffer_ptr = Data(buffer[]).cpp_object
        result = unsafe_pointer_to_objref(buffer_ptr)
        @test typeof(result) == typeof(data)
        @test result === data
    end

    # TODO: Using `sizeof` is probably wrong for `pointer_from_objref` as there is probably
    # additional Julia type metadata not being accounted for. This may be why we see a
    # segfault when trying to use `pointer_from_objref`.
    # https://github.com/beacon-biosignals/Ray.jl/issues/55
    @testset "copied object reference" begin
        buffer = LocalMemoryBuffer(pointer_from_objref(data), sizeof(data), true)
        @test Data(buffer[]) != pointer_from_objref(data)
        @test Size(buffer[]) == sizeof(data)
        @test OwnsData(buffer[])
        @test !IsPlasmaBuffer(buffer[])

        # Attempting to use:
        # `buffer_ptr = Data(buffer[]).cpp_object; unsafe_pointer_to_objref(buffer_ptr)`
        # would result in a segfault.
    end

    @testset "copied data pointer" begin
        buffer = LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true)
        @test Data(buffer[]) != pointer(data)
        @test Size(buffer[]) == sizeof(data)
        @test OwnsData(buffer[])
        @test !IsPlasmaBuffer(buffer[])

        buffer_ptr = Data(buffer[]).cpp_object
        buffer_size = Size(buffer[])
        T = eltype(data)
        len = Size(buffer[]) ÷ sizeof(T)
        result = Vector{T}(undef, len)
        unsafe_copyto!(Ptr{UInt8}(pointer(result)), buffer_ptr, buffer_size)
        @test typeof(result) == typeof(data)
        @test result == data
        @test result !== data
    end

    @testset "copied serialized object" begin
        serialized = Vector{UInt8}(sprint(serialize, data))
        buffer = LocalMemoryBuffer(serialized, sizeof(serialized), true)
        @test Size(buffer[]) == sizeof(serialized)
        @test OwnsData(buffer[])
        @test !IsPlasmaBuffer(buffer[])

        buffer_ptr = Data(buffer[]).cpp_object
        buffer_size = Size(buffer[])
        v = Vector{UInt8}(undef, buffer_size)
        unsafe_copyto!(pointer(v), buffer_ptr, buffer_size)
        result = deserialize(IOBuffer(v))
        @test typeof(result) == typeof(data)
        @test result == data
        @test result !== data
    end
end
