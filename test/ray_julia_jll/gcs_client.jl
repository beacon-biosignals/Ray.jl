@testset "GCS client" begin
    using UUIDs
    using .ray_julia_jll: JuliaGcsClient, Connect, Put, Get, Keys, Exists, Status, ok,
                          ToString, Disconnect

    client = JuliaGcsClient("127.0.0.1:6379")

    ns = string("TESTING-", uuid4())

    # throws if not connected
    @test_throws ErrorException Put(client, ns, "computer", "mistaek", false)
    @test_throws ErrorException Get(client, ns, "computer")
    @test_throws ErrorException Keys(client, ns, "")
    @test_throws ErrorException Exists(client, ns, "computer")

    Connect(client) do client

        @test Put(client, ns, "computer", "mistaek", false) == 1
        @test Get(client, ns, "computer") == "mistaek"
        @test Keys(client, ns, "") == ["computer"]
        @test Keys(client, ns, "comp") == ["computer"]
        @test Keys(client, ns, "comppp") == []
        @test Exists(client, ns, "computer")

        # no overwrite
        @test Put(client, ns, "computer", "blah", false) == 0
        @test Get(client, ns, "computer") == "mistaek"

        # overwrite ("added" only increments on new key I think)
        @test Put(client, ns, "computer", "blah", true) == 0
        @test Get(client, ns, "computer") == "blah"

        # throw on missing key
        @test_throws ErrorException Get(client, ns, "none")

    end
        # Disconnect(client)
end
