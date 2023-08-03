using Revise, ray_core_worker_julia_jll, Test

# TODO: These tests are getting into implementation details of LocalMemoryBuffer (which should be avoided).
# For now, this is just helping us understand our C++ wrapper better

# @testset "LocalMemoryBuffer" begin
    data = UInt8[1:3;]
    buffer = ray_core_worker_julia_jll.LocalMemoryBuffer(pointer_from_objref(data), sizeof(data), false)
    @test ray_core_worker_julia_jll.Size(buffer) == length(data)
    @test !ray_core_worker_julia_jll.OwnsData(buffer)
    @test !ray_core_worker_julia_jll.IsPlasmaBuffer(buffer)

    buffer_data = unsafe_pointer_to_objref(ray_core_worker_julia_jll.Data(buffer).cpp_object)
    @test buffer_data isa Vector{UInt8}
    @test buffer_data === data

    buffer = ray_core_worker_julia_jll.LocalMemoryBuffer(pointer_from_objref(data), sizeof(data), true)
    @test ray_core_worker_julia_jll.Size(buffer) == length(data)
    @test ray_core_worker_julia_jll.OwnsData(buffer)
    @test !ray_core_worker_julia_jll.IsPlasmaBuffer(buffer)

    p = ray_core_worker_julia_jll.Data(buffer).cpp_object

# end

