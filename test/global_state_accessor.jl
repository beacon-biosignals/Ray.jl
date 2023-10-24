@testset "GlobalStateAccessor" begin
    using Ray: GLOBAL_STATE_ACCESSOR, NODE_IP_ADDRESS, get_node_to_connect_for_driver,
               GCS_ADDRESS_FILE

    gcs_address = read(GCS_ADDRESS_FILE, String)
    opts = ray_jll.GcsClientOptions(gcs_address)
    GLOBAL_STATE_ACCESSOR[] = ray_jll.GlobalStateAccessor(opts)
    ray_jll.Connect(GLOBAL_STATE_ACCESSOR[])

    # Note: passing in a fake node IP address won't throw an error, instead it reports a
    # RAY_LOG(INFO) message about not finding a local Raylet with that address
    # https://github.com/beacon-biosignals/ray/blob/448a83caf44108fc1bc44fa7c6c358cffcfcb0d7/src/ray/gcs/gcs_client/global_state_accessor.cc#L356-L359
    raylet, store, node_port = get_node_to_connect_for_driver(GLOBAL_STATE_ACCESSOR[],
                                                              NODE_IP_ADDRESS)

    raylet_regex = r"^/tmp/ray/session_[0-9_-]+/sockets/raylet"
    @test occursin(raylet_regex, String(raylet))

    store_regex = r"^/tmp/ray/session_[0-9_-]+/sockets/plasma_store"
    @test occursin(store_regex, String(store))

    @test node_port isa Number

    ray_jll.Disconnect(GLOBAL_STATE_ACCESSOR[])
end
