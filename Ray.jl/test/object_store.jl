@testset "object_store.jl" begin

    # Int
    oid = put(1)
    @test Ray.get(oid) == 1

    # Float
    oid = put(1.23)
    @test Ray.get(oid) == 1.23

    # String
    oid = put("hello")
    @test Ray.get(oid) == "hello"

    # Tuple
    oid = put((1, 2, 3))
    @test Ray.get(oid) == (1, 2, 3)

    # Vector
    oid = put([1, 2, 3])
    @test Ray.get(oid) == [1, 2, 3]

end
