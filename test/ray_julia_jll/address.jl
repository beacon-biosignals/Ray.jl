@testset "Address" begin
    using .ray_julia_jll: Address, NodeID, WorkerID, FromBinary, Hex

    @testset "equality" begin
        addr = Address()
        @test addr == Address()
        @test addr == CxxPtr(Address())[]
    end

    @testset "json round-trip" begin
        json = Dict(:rayletId => base64encode("raylet"), :ipAddress => "127.0.0.1",
                    :port => 10000, :workerId => base64encode("worker"))
        json_str = JSON3.write(json)
        address = ray_julia_jll.JsonStringToMessage(Address, json_str)
        result = ray_julia_jll.MessageToJsonString(address)
        @test JSON3.read(String(result)) == json
    end

    @testset "serialized round-trip" begin
        serialized_str = "\n\x06raylet\x12\t127.0.0.1\x18\x90N\"\x06worker"
        address = ray_julia_jll.ParseFromString(Address, serialized_str)
        result = ray_julia_jll.SerializeAsString(address)
        @test result == serialized_str
    end

    @testset "julia serialization round-trip" begin
        addr_alloc = Address()
        @test addr_alloc isa ray_julia_jll.AddressAllocated
        serialized_addr_alloc = sprint(serialize, addr_alloc)
        result = deserialize(IOBuffer(serialized_addr_alloc))
        @test result isa ray_julia_jll.AddressAllocated
        @test result == addr_alloc

        addr_ptr = CxxPtr(addr_alloc)
        addr_deref = addr_ptr[]
        @test addr_deref isa ray_julia_jll.AddressDereferenced
        serialized_addr_deref = sprint(serialize, addr_deref)
        result = deserialize(IOBuffer(serialized_addr_deref))
        @test result isa ray_julia_jll.AddressAllocated
        @test result == addr_deref

        @test serialized_addr_deref == serialized_addr_alloc
    end

    @testset "namedtuple constructor" begin
        nt = (; raylet_id="a"^(2 * 28), ip_address="127.0.0.1", port=1000, worker_id="b" ^ (2 * 28))
        addr = Address(nt)
        @test Hex(FromBinary(NodeID, ray_julia_jll.raylet_id(addr))) == nt.raylet_id
        @test ray_julia_jll.ip_address(addr)[] == nt.ip_address
        @test ray_julia_jll.port(addr) == nt.port
        @test Hex(FromBinary(WorkerID, ray_julia_jll.worker_id(addr))) == nt.worker_id
    end

    @testset "show" begin
        nt = (; raylet_id="a"^(2 * 28), ip_address="127.0.0.1", port=1000, worker_id="b" ^ (2 * 28))
        expected = "Address((raylet_id=\"$(nt.raylet_id)\", ip_address=\"$(nt.ip_address)\", " *
                   "port=$(nt.port), worker_id=\"$(nt.worker_id)\"))"
        @test sprint(show, Address(nt)) == expected
    end
end
