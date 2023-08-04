using Serialization: deserialize, serialize
using Test
using ray_core_worker_julia_jll: LocalMemoryBuffer, data_pointer, owns_data, is_plasma_buffer

@testset "LocalMemoryBuffer" begin
    data = UInt16[1:3;]

    @testset "non-copied object reference" begin
        buffer = LocalMemoryBuffer(pointer_from_objref(data), sizeof(data), false)
        @test data_pointer(buffer) == pointer_from_objref(data)
        @test sizeof(buffer) == sizeof(data)
        @test !owns_data(buffer)
        @test !is_plasma_buffer(buffer)

        result = unsafe_pointer_to_objref(data_pointer(buffer))
        @test typeof(result) == typeof(data)
        @test result === data
    end

    # TODO: Using `sizeof` is probably wrong for `pointer_from_objref` as there is probably
    # additional Julia type metadata not being accounted for. This may be why we see a
    # segfault when trying to use `pointer_from_objref`.
    @testset "copied object reference" begin
        buffer = LocalMemoryBuffer(pointer_from_objref(data), sizeof(data), true)
        @test data_pointer(buffer) != pointer_from_objref(data)
        @test sizeof(buffer) == sizeof(data)
        @test owns_data(buffer)
        @test !is_plasma_buffer(buffer)

        # Attempting to use `unsafe_pointer_to_objref(data_pointer(buffer))` would result in a
        # segfault.
    end

    @testset "copied data pointer" begin
        buffer = LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true)
        @test data_pointer(buffer) != pointer(data)
        @test sizeof(buffer) == sizeof(data)
        @test owns_data(buffer)
        @test !is_plasma_buffer(buffer)

        T = eltype(data)
        len = sizeof(buffer) ÷ sizeof(T)
        result = Vector{T}(undef, len)
        unsafe_copyto!(Ptr{UInt8}(pointer(result)), data_pointer(buffer), sizeof(buffer))
        @test typeof(result) == typeof(data)
        @test result == data
        @test result !== data
    end

    @testset "copied serialized object" begin
        serialized = Vector{UInt8}(sprint(serialize, data))
        buffer = LocalMemoryBuffer(serialized, sizeof(serialized), true)
        @test sizeof(buffer) == sizeof(serialized)
        @test owns_data(buffer)
        @test !is_plasma_buffer(buffer)

        v = Vector{UInt8}(undef, sizeof(buffer))
        unsafe_copyto!(pointer(v), data_pointer(buffer), sizeof(buffer))
        result = deserialize(IOBuffer(v))
        @test typeof(result) == typeof(data)
        @test result == data
        @test result !== data
    end
end
