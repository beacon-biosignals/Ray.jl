@testset "GCS client" begin
    using UUIDs
    using ray_core_worker_julia_jll: JuliaGcsClient, Connect,
                                     Put, Get, Keys, Exists,
                                     Status, ok, ToString

    client = JuliaGcsClient("127.0.0.1:6379")

    ns = string("TESTING-", uuid4())

    # throws if not connected
    @test_throws ErrorException Put(client, ns, "computer", "mistaek", false, -1)
    @test_throws ErrorException Get(client, ns, "computer", -1)
    @test_throws ErrorException Keys(client, ns, "", -1)
    @test_throws ErrorException Exists(client, ns, "computer", -1)

    status = Connect(client)
    @test ok(status)
    @test ToString(status) == "OK"

    @test Put(client, ns, "computer", "mistaek", false, -1) == 1
    @test Get(client, ns, "computer", -1) == "mistaek"
    @test Keys(client, ns, "", -1) == ["computer"]
    @test Keys(client, ns, "comp", -1) == ["computer"]
    @test Keys(client, ns, "comppp", -1) == []
    @test Exists(client, ns, "computer", -1)

    # no overwrite
    @test Put(client, ns, "computer", "blah", false, -1) == 0
    @test Get(client, ns, "computer", -1) == "mistaek"

    # overwrite ("added" only increments on new key I think)
    @test Put(client, ns, "computer", "blah", true, -1) == 0
    @test Get(client, ns, "computer", -1) == "blah"

    # throw on missing key
    @test_throws ErrorException Get(client, ns, "none", -1)

    # ideally we'd throw on connect but it returns OK......
    badclient = JuliaGcsClient("127.0.0.1:6378")
    status = Connect(badclient)

    # ...but then throws when we try to do anything so at least there's that
    @test_throws ErrorException Put(badclient, ns, "computer", "mistaek", false, -1)
end
