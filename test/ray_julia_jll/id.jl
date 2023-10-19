using .ray_julia_jll: JobID, ObjectID, TaskID

@testset "$T (shared code)" for T in (ObjectID,)
    using .ray_julia_jll: ray_julia_jll, BaseID, Binary, FromBinary, FromHex, FromRandom, Hex

    T_Allocated = @eval ray_julia_jll.$(Symbol(nameof(T), :Allocated))
    T_Dereferenced = @eval ray_julia_jll.$(Symbol(nameof(T), :Dereferenced))
    Alt = T === ObjectID ? JobID : ObjectID

    @testset "supertype" begin
        @test T <: BaseID
    end

    @testset "FromRandom" begin
        id = FromRandom(T)
        @test id isa T
        @test ncodeunits(Hex(id)) == 2 * 28
    end

    @testset "FromHex" begin
        id = FromHex(T, "a"^(2 * 28))
        @test id isa T
        @test Hex(id) == "a"^(2 * 28)

        @test_throws ArgumentError FromHex(T, "a")
        @test_throws ArgumentError FromHex(T, "a"^(2 * 27))
        @test_throws ArgumentError FromHex(T, "a"^(2 * 29))
    end

    @testset "FromBinary" begin
        bytes = fill(0xbb, 28)
        bytes_str = String(deepcopy(bytes))
        @test length(bytes) == 28

        id = FromBinary(T, bytes)
        @test length(bytes) == 28  # Bytes are not consumed by constructor
        @test id isa ObjectID
        @test Binary(Vector{UInt8}, id) == bytes
        @test Binary(String, id) == bytes_str

        id = FromBinary(T, bytes_str)
        @test id isa T
        @test Binary(Vector{UInt8}, id) == bytes
        @test Binary(String, id) == bytes_str

        @test_throws ArgumentError FromBinary(T, fill(0xbb, 1))
        @test_throws ArgumentError FromBinary(T, fill(0xbb, 27))
        @test_throws ArgumentError FromBinary(T, fill(0xbb, 29))
    end

    @testset "string constructor" begin
        hex_str = "c"^(2 * 28)
        @test Hex(T(hex_str)) == Hex(FromHex(T, hex_str))
    end

    @testset "show" begin
        hex_str = "d"^(2 * 28)
        id = FromHex(T, hex_str)
        @test sprint(show, id) == "$T(\"$hex_str\")"
    end

    @testset "equality" begin
        id_alloc = FromRandom(T)
        id_deref = CxxRef(id_alloc)[]
        @test id_alloc isa T_Allocated
        @test id_deref isa T_Dereferenced

        @test id_alloc == id_deref
        @test id_deref == id_alloc

        id_alloc2 = FromHex(T, Hex(id_alloc))
        @test id_alloc2 !== id_alloc
        @test id_alloc2 == id_alloc

        id_deref2 = CxxRef(FromHex(ObjectID, Hex(id_alloc)))[]
        @test id_deref2 !== id_deref
        # confirm C++ pointers are different too
        @test id_deref2.cpp_object != id_deref.cpp_object
        @test id_deref2 == id_deref

        @test hash(id_alloc) == hash(id_deref)
        @test hash(id_alloc) != hash(Alt(Hex(id_alloc)))
        @test issetequal([id_deref, id_deref2, id_alloc2], [id_alloc])
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
