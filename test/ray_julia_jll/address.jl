using .ray_julia_jll: Address

@testset "Address" begin
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
        address = Address()
        io = IOBuffer()
        serialize(io, address)
        seekstart(io)
        result = deserialize(io)
        @test result == address
    end
end
