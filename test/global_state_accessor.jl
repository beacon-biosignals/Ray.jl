@testset "GlobalStateAccessor" begin
    using Ray: GLOBAL_STATE_ACCESSOR, get_node_to_connect_for_driver, get_node_ip_address,
               GCS_ADDRESS_FILE, DEFAULT_SESSION_DIR

    gcs_address = read(GCS_ADDRESS_FILE, String)
    opts = ray_jll.GcsClientOptions(gcs_address)
    GLOBAL_STATE_ACCESSOR[] = ray_jll.GlobalStateAccessor(opts)
    ray_jll.Connect(GLOBAL_STATE_ACCESSOR[])

    node_ip_address = get_node_ip_address(DEFAULT_SESSION_DIR)

    # Note: passing in a fake node IP address won't throw an error, instead it reports a
    # RAY_LOG(INFO) message about not finding a local Raylet with that address
    # https://github.com/beacon-biosignals/ray/blob/448a83caf44108fc1bc44fa7c6c358cffcfcb0d7/src/ray/gcs/gcs_client/global_state_accessor.cc#L356-L359
    raylet, store, node_port = get_node_to_connect_for_driver(GLOBAL_STATE_ACCESSOR[],
                                                              node_ip_address)

    @test raylet isa StdString
    @test occursin(r"^/tmp/ray/session_[0-9_-]+/sockets/raylet", raylet)
    @test store isa StdString
    @test occursin(r"^/tmp/ray/session_[0-9_-]+/sockets/plasma_store", store)
    @test node_port isa Integer
    @test 0 <= node_port <= 65535

    ray_jll.Disconnect(GLOBAL_STATE_ACCESSOR[])
end
