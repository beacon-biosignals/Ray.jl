# Using `ObjectID` and `JobID` to validate `BaseID` methods
@testset "BaseID" begin
    using .ray_julia_jll: ray_julia_jll, JobID, ObjectID, Binary, FromBinary, FromHex, FromRandom,
                          Hex

    @testset "FromRandom" begin
        object_id = FromRandom(ObjectID)
        @test object_id isa ObjectID
        @test ncodeunits(Hex(object_id)) == 2 * 28
    end

    @testset "FromHex" begin
        object_id = FromHex(ObjectID, "a"^(2 * 28))
        @test object_id isa ObjectID
        @test Hex(object_id) == "a"^(2 * 28)

        @test_throws ArgumentError FromHex(ObjectID, "a")
        @test_throws ArgumentError FromHex(ObjectID, "a"^(2 * 27))
        @test_throws ArgumentError FromHex(ObjectID, "a"^(2 * 29))
    end

    @testset "FromBinary" begin
        bytes = fill(0xbb, 28)
        bytes_str = String(deepcopy(bytes))
        @test length(bytes) == 28

        object_id = FromBinary(ObjectID, bytes)
        @test length(bytes) == 28  # Bytes are not consumed by constructor
        @test object_id isa ObjectID
        @test Binary(Vector{UInt8}, object_id) == bytes
        @test Binary(String, object_id) == bytes_str

        object_id = FromBinary(ObjectID, bytes_str)
        @test object_id isa ObjectID
        @test Binary(Vector{UInt8}, object_id) == bytes
        @test Binary(String, object_id) == bytes_str

        @test_throws ArgumentError FromBinary(ObjectID, fill(0xbb, 1))
        @test_throws ArgumentError FromBinary(ObjectID, fill(0xbb, 27))
        @test_throws ArgumentError FromBinary(ObjectID, fill(0xbb, 29))
    end

    @testset "string constructor" begin
        hex_str = "c"^(2 * 28)
        @test Hex(ObjectID(hex_str)) == Hex(FromHex(ObjectID, hex_str))
    end

    @testset "show" begin
        hex_str = "d"^(2 * 28)
        object_id = FromHex(ObjectID, hex_str)
        @test sprint(show, object_id) == "ObjectID(\"$hex_str\")"
    end

    @testset "equality" begin
        oid_alloc = FromRandom(ObjectID)
        oid_deref = CxxRef(oid_alloc)[]
        @test oid_alloc isa ray_julia_jll.ObjectIDAllocated
        @test oid_deref isa ray_julia_jll.ObjectIDDereferenced

        @test oid_alloc == oid_deref
        @test oid_deref == oid_alloc

        oid_alloc2 = FromHex(ObjectID, Hex(oid_alloc))
        @test oid_alloc2 !== oid_alloc
        @test oid_alloc2 == oid_alloc

        oid_deref2 = CxxRef(FromHex(ObjectID, Hex(oid_alloc)))[]
        @test oid_deref2 !== oid_deref
        # confirm C++ pointers are different too
        @test oid_deref2.cpp_object != oid_deref.cpp_object
        @test oid_deref2 == oid_deref

        @test hash(oid_alloc) == hash(oid_deref)
        @test hash(oid_alloc) != hash(JobID(Hex(oid_alloc)))
        @test issetequal([oid_deref, oid_deref2, oid_alloc2], [oid_alloc])
    end
end

@testset "ObjectID" begin
    using .ray_julia_jll: BaseID, ObjectID, FromHex, FromNil, Hex

    @testset "supertype" begin
        @test ObjectID <: BaseID
    end

    @testset "constructors" begin
        object_id = FromNil(ObjectID)
        @test object_id isa ObjectID
        @test Hex(object_id) == "f"^(2 * 28)
    end
end
