@testset "Reference counting" begin
    using .ray_julia_jll: FromRandom, ObjectID, Hex, AddLocalReference,
                          RemoveLocalReference, GetAllReferenceCounts, _keys, _getindex,
                          GetCoreWorker

    worker = GetCoreWorker()
    # need to convert to hex string because these are just pointers
    has_count(oid) = Hex(oid) in Hex.(_keys(GetAllReferenceCounts(worker)))
    local_count(oid) = first(_getindex(GetAllReferenceCounts(worker), oid))

    oid = FromRandom(ObjectID)

    @test !has_count(oid)

    AddLocalReference(worker, oid)
    @test has_count(oid)
    @test local_count(oid) == 1

    AddLocalReference(worker, oid)
    @test local_count(oid) == 2

    RemoveLocalReference(worker, oid)
    @test local_count(oid) == 1

    RemoveLocalReference(worker, oid)
    @test !has_count(oid)
    @test local_count(oid) == 0

    RemoveLocalReference(worker, oid)
    @test !has_count(oid)
    @test local_count(oid) == 0
end
