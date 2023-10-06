using .ray_julia_jll: Buffer, LocalMemoryBuffer, NullPtr, ObjectReference, RayObject,
                      get_data, get_metadata

@testset "RayObject" begin
    @testset "get_data / get_metadata" begin
        @testset "non-null data/metadata" begin
            data = UInt16[1:3;]
            metadata = b"22"

            data_buf = LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true)
            metadata_buf = LocalMemoryBuffer(Ptr{Nothing}(pointer(metadata)), sizeof(metadata), true)
            nested_refs = StdVector{ObjectReference}()
            ray_obj = RayObject(data_buf, metadata_buf, nested_refs, false)

            result = get_data(ray_obj)
            @test result isa Vector{UInt8}
            @test result == reinterpret(UInt8, data)

            result = get_metadata(ray_obj)
            @test result isa Vector{UInt8}
            @test result == metadata
        end

        @testset "null data" begin
            metadata = b"22"

            data_buf = NullPtr(Buffer)
            metadata_buf = LocalMemoryBuffer(Ptr{Nothing}(pointer(metadata)), sizeof(metadata), true)
            nested_refs = StdVector{ObjectReference}()
            ray_obj = RayObject(data_buf, metadata_buf, nested_refs, false)

            @test get_data(ray_obj) === nothing
            @test get_metadata(ray_obj) == metadata
        end

        @testset "null metadata" begin
            data = UInt16[1:3;]

            data_buf = LocalMemoryBuffer(Ptr{Nothing}(pointer(data)), sizeof(data), true)
            metadata_buf = NullPtr(Buffer)
            nested_refs = StdVector{ObjectReference}()
            ray_obj = RayObject(data_buf, metadata_buf, nested_refs, false)

            @test get_data(ray_obj) == reinterpret(UInt8, data)
            @test get_metadata(ray_obj) === nothing
        end
    end
end
