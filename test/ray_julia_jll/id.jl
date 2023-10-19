using .ray_julia_jll: JobID, NodeID, ObjectID, TaskID, WorkerID

@testset "$T (shared code)" for T in (ObjectID, JobID, TaskID, WorkerID, NodeID)
    using .ray_julia_jll: ray_julia_jll, BaseID, Binary, FromBinary, FromHex, FromRandom, Hex

    T_Allocated = @eval ray_julia_jll.$(Symbol(nameof(T), :Allocated))
    T_Dereferenced = @eval ray_julia_jll.$(Symbol(nameof(T), :Dereferenced))
    siz = ray_julia_jll.Size(T)

    @testset "supertype" begin
        @test T <: BaseID
    end

    if hasmethod(FromRandom, Tuple{Type{T}})
        @testset "FromRandom" begin
            id = FromRandom(T)
            @test id isa T
            @test ncodeunits(Hex(id)) == 2 * siz
        end
    end

    @testset "FromHex" begin
        id = FromHex(T, "a"^(2 * siz))
        @test id isa T
        @test Hex(id) == "a"^(2 * siz)

        @test_throws ArgumentError FromHex(T, "a")
        @test_throws ArgumentError FromHex(T, "a"^(2 * (siz - 1)))
        @test_throws ArgumentError FromHex(T, "a"^(2 * (siz + 1)))
    end

    @testset "FromBinary" begin
        bytes = fill(0xbb, siz)
        bytes_str = String(deepcopy(bytes))
        @test length(bytes) == siz

        id = FromBinary(T, bytes)
        @test length(bytes) == siz  # Bytes are not consumed by constructor
        @test id isa T
        @test Binary(Vector{UInt8}, id) == bytes
        @test Binary(String, id) == bytes_str

        id = FromBinary(T, bytes_str)
        @test id isa T
        @test Binary(Vector{UInt8}, id) == bytes
        @test Binary(String, id) == bytes_str

        @test_throws ArgumentError FromBinary(T, fill(0xbb, 1))
        @test_throws ArgumentError FromBinary(T, fill(0xbb, siz - 1))
        @test_throws ArgumentError FromBinary(T, fill(0xbb, siz + 1))
    end

    @testset "equality" begin
        hex_str = "e"^(2 * siz)
        id_alloc = FromHex(T, hex_str)
        id_deref = CxxRef(id_alloc)[]
        @test id_alloc isa T_Allocated
        @test id_deref isa T_Dereferenced

        @test id_alloc == id_deref
        @test id_deref == id_alloc

        id_alloc2 = FromHex(T, hex_str)
        @test id_alloc2 !== id_alloc
        @test id_alloc2 == id_alloc

        id_deref2 = CxxRef(FromHex(T, hex_str))[]
        @test id_deref2 !== id_deref
        # confirm C++ pointers are different too
        @test id_deref2.cpp_object != id_deref.cpp_object
        @test id_deref2 == id_deref

        @test hash(id_alloc) == hash(id_deref)
        @test issetequal([id_deref, id_deref2, id_alloc2], [id_alloc])
    end
end

@testset "ObjectID" begin
    using .ray_julia_jll: ObjectID, FromHex, FromNil, Hex

    @testset "FromNil" begin
        object_id = FromNil(ObjectID)
        @test object_id isa ObjectID
        @test Hex(object_id) == "f"^(2 * 28)
    end

    @testset "string constructor" begin
        hex_str = "c"^(2 * 28)
        @test Hex(ObjectID(hex_str)) == Hex(FromHex(ObjectID, hex_str))
    end

    @testset "show" begin
        hex_str = "d"^(2 * 28)
        @test sprint(show, ObjectID(hex_str)) == "ObjectID(\"$hex_str\")"
    end
end

@testset "JobID" begin
    using .ray_julia_jll: JobID, FromInt, ToInt

    @testset "FromInt" begin
        job_id = FromInt(JobID, 1)
        @test job_id isa JobID
        @test ToInt(job_id) == 1
    end

    @testset "string constructor" begin
        @test JobID(2) == FromInt(JobID, 2)
    end

    @testset "show" begin
        @test sprint(show, JobID(3)) == "JobID(3)"
    end
end

@testset "TaskID" begin
    using .ray_julia_jll: TaskID, FromHex, Hex

    @testset "string constructor" begin
        hex_str = "c"^(2 * 24)
        @test TaskID(hex_str) == FromHex(TaskID, hex_str)
    end

    @testset "show" begin
        hex_str = "d"^(2 * 24)
        @test sprint(show, TaskID(hex_str)) == "TaskID(\"$hex_str\")"
    end
end

@testset "WorkerID" begin
    using .ray_julia_jll: WorkerID, FromHex, Hex

    @testset "string constructor" begin
        hex_str = "c"^(2 * 28)
        @test WorkerID(hex_str) == FromHex(WorkerID, hex_str)
    end

    @testset "show" begin
        hex_str = "d"^(2 * 28)
        @test sprint(show, WorkerID(hex_str)) == "WorkerID(\"$hex_str\")"
    end
end

@testset "NodeID" begin
    using .ray_julia_jll: NodeID, FromHex, Hex

    @testset "string constructor" begin
        hex_str = "c"^(2 * 28)
        @test NodeID(hex_str) == FromHex(NodeID, hex_str)
    end

    @testset "show" begin
        hex_str = "d"^(2 * 28)
        @test sprint(show, NodeID(hex_str)) == "NodeID(\"$hex_str\")"
    end
end
