@testset "GCS client" begin
    using UUIDs
    using .ray_julia_jll: JuliaGcsClient, Connect, Disconnect, Del, Put, Get, Keys, Exists

    client = JuliaGcsClient("127.0.0.1:6379")
    @test isnothing(Disconnect(client))

    ns = string("TESTING-", uuid4())

    # throws if not connected
    @test_throws ErrorException Put(client, ns, "computer", "mistaek", false)
    @test_throws ErrorException Get(client, ns, "computer")
    @test_throws ErrorException Keys(client, ns, "")
    @test_throws ErrorException Exists(client, ns, "computer")

    Connect(client) do client
        added = Put(client, ns, "computer", "mistaek", false)
        @test added isa Bool
        @test added == true

        result = Get(client, ns, "computer")
        @test result isa StdString
        @test result == "mistaek"

        results = Keys(client, ns, "")
        @test results isa StdVector{StdString}
        @test results == ["computer"]

        @test Keys(client, ns, "comp") == ["computer"]
        @test Keys(client, ns, "comppp") == []

        exists = Exists(client, ns, "computer")
        @test exists isa Bool
        @test exists == true

        # no overwrite
        @test !Put(client, ns, "computer", "blah", false)
        @test Get(client, ns, "computer") == "mistaek"

        # overwrite ("added" only increments on new key I think)
        @test !Put(client, ns, "computer", "blah", true)
        @test Get(client, ns, "computer") == "blah"

        # delete
        result = Del(client, ns, "computer", false)
        @test result isa Nothing
        @test !Exists(client, ns, "computer")

        # deleting a non-existent key doesn't fail
        Del(client, ns, "computer", false)

        # throw on missing key
        @test_throws ErrorException Get(client, ns, "computer")
    end
end
