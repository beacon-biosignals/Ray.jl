using .ray_julia_jll: LocalMemoryBuffer, ObjectReference, RayObject, get_data_metadata

@testset "RayObject" begin
    @testset "get_data_metadata" begin
        data = UInt16[1:3;]
        metadata = b"22"
        data_buf = LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true)
        metadata_buf = LocalMemoryBuffer(Ptr{Nothing}(pointer(metadata)), sizeof(metadata), true)
        nested_refs = StdVector{ObjectReference}()

        ray_obj = RayObject(data_buf, metadata_buf, nested_refs, false)
        result = get_data_metadata(ray_obj)

        @test result isa Tuple{Vector{UInt8}, String}
        @test result[1] == reinterpret(UInt8, data)
        @test result[2] == String(metadata)
    end
end
