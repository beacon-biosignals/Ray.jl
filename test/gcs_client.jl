@testset "GCS client" begin
    using ray_core_worker_julia_jll: Put, Get, Connect, JuliaGcsClient,
                                     Status, ok, ToString

    client = JuliaGcsClient("127.0.0.1:6379")
    added = Ref{Cint}()

    # throws if not connected
    @test_throws ErrorException Put(client, "TESTING", "computer", "mistaek", false, -1, added)
    @test_throws ErrorException Get(client, "TESTING", "computer", -1)

    status = Connect(client)
    @test ok(status)
    @test ToString(status) == "OK"

    @test Put(client, "TESTING", "computer", "mistaek", false, -1, added) === nothing
    @test added[] == 1

    @test Put(client, "TESTING", "computer", "mistaek", false, -1, added) === nothing
    @test added[] == 0

    @test Get(client, "TESTING", "computer", -1) == "mistaek"

    # no overwrite
    @test Put(client, "TESTING", "computer", "blah", false, -1, added) === nothing
    @test Get(client, "TESTING", "computer", -1) == "mistaek"

    # overwrite
    @test Put(client, "TESTING", "computer", "blah", true, -1, added) === nothing
    @test Get(client, "TESTING", "computer", -1) == "blah"
    # added only increments on new key I think?
    @test added[] == 0

    # throw on missing key
    @test_throws ErrorException Get(client, "TESTING", "none", -1)

    # ideally we'd throw on connect but it returns OK......
    badclient = JuliaGcsClient("127.0.0.1:6378")
    status = Connect(badclient)

    # ...but then throws when we try to do anything so at least there's that
    @test_throws ErrorException Put(badclient, "TESTING", "computer", "mistaek", false, -1, added)
end
