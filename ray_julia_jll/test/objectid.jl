@testset "ObjectID" begin
    using ray_julia_jll: ObjectID, FromRandom, FromHex, Hex
    # need to get some ObjectIDDereferenced
    objs = CxxWrap.StdVector{ObjectID}()
    obj = FromRandom(ObjectID)
    push!(objs, obj)
    push!(objs, obj)

    obj_deref = objs[1]
    @test obj_deref isa ray_julia_jll.ObjectIDDereferenced
    @test obj isa ray_julia_jll.ObjectIDAllocated

    @test obj_deref == obj
    @test obj == obj_deref

    obj2 = FromHex(ObjectID, Hex(obj))
    @test obj2 !== obj
    @test obj2 == obj

    obj_deref2 = objs[2]
    @test obj_deref2 !== obj_deref
    # confirm C++ pointers are different too
    @test obj_deref2.cpp_object != obj_deref.cpp_object
    @test obj_deref2 == obj_deref

    @test hash(obj_deref) == hash(obj)

    @test issetequal(objs, [obj])
end
