# this runs inside setup_core_worker()

function serialize_deserialize(x)
    io = IOBuffer()
    serialize(io, x)
    seekstart(io)
    return deserialize(io)
end

@testset "ObjectRef" begin
    @testset "basic" begin
        hex_str = "f" ^ (2 * 28)
        obj_ref = ObjectRef(hex_str)
        @test Ray.hex_identifier(obj_ref) == hex_str
        @test obj_ref == ObjectRef(hex_str)
        @test hash(obj_ref) == hash(ObjectRef(hex_str))
    end

    @testset "show" begin
        hex_str = "f" ^ (2 * 28)
        obj_ref = ObjectRef(hex_str)
        @test sprint(show, obj_ref) == "ObjectRef(\"$hex_str\")"
    end

    # Note: Serializing `ObjectRef` requires the core worker to be initialized
    @testset "serialize/deserialize" begin
        obj_ref1 = ObjectRef(ray_jll.FromRandom(ray_jll.ObjectID))
        obj_ref2 = serialize_deserialize(obj_ref1)
        @test obj_ref1 == obj_ref2
    end
end

@testset "Local reference counting" begin
    using ray_julia_jll: Hex
    obj = Ray.put(nothing)
    oid = obj.oid_hex

    local_count(o::ObjectRef) = local_count(o.oid_hex)
    local_count(oid_hex) = first(get(Ray.get_all_reference_counts(), oid_hex, 0))

    @test local_count(obj) == 1

    obj2 = deepcopy(obj)
    @test local_count(obj) == 2

    finalize(obj2)
    # insert yield point here to allow async task that makes the API call to run
    yield()
    @test local_count(obj) == 1

    finalize(obj)
    yield()
    @test local_count(oid) == 0
end
