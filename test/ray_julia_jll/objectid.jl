@testset "ObjectID" begin
    using .ray_julia_jll: ObjectID, FromRandom, FromHex, Hex

    obj = FromRandom(ObjectID)
    obj_deref = CxxRef(FromHex(ObjectID, Hex(obj)))[]
    @test obj_deref isa ray_julia_jll.ObjectIDDereferenced
    @test obj isa ray_julia_jll.ObjectIDAllocated

    @test obj_deref == obj
    @test obj == obj_deref

    obj2 = FromHex(ObjectID, Hex(obj))
    @test obj2 !== obj
    @test obj2 == obj

    obj_deref2 = CxxRef(FromHex(ObjectID, Hex(obj)))[]
    @test obj_deref2 !== obj_deref
    # confirm C++ pointers are different too
    @test obj_deref2.cpp_object != obj_deref.cpp_object
    @test obj_deref2 == obj_deref

    @test hash(obj_deref) == hash(obj)

    @test issetequal([obj_deref, obj_deref2, obj2], [obj])
end
