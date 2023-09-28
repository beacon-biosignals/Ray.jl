@testset "flatten_args" begin
    result = Ray.flatten_args((), (;))
    @test result isa Vector{Pair{Symbol,Any}}
    @test isempty(result)

    result = Ray.flatten_args((1, "2", 3 // 1), (;))
    @test result isa Vector{Pair{Symbol,Any}}
    @test result == [Ray.ARG_KEY => 1, Ray.ARG_KEY => "2", Ray.ARG_KEY => 3 // 1]

    result = Ray.flatten_args((), (; x=1, y="2"))
    @test result isa Vector{Pair{Symbol,Any}}
    @test result == [:x => 1, :y => "2"]

    result = Ray.flatten_args((1, "2"), (; x='3', y=0x4))
    @test result isa Vector{Pair{Symbol,Any}}
    @test result == [Ray.ARG_KEY => 1, Ray.ARG_KEY => "2", :x => '3', :y => 0x4]
end

@testset "recover_args" begin
    args, kwargs = Ray.recover_args([])
    @test args isa Vector{Any}
    @test isempty(args)
    @test kwargs isa Vector{Pair{Symbol,Any}}
    @test isempty(kwargs)

    args, kwargs = Ray.recover_args([Ray.ARG_KEY => 1])
    @test args isa Vector{Any}
    @test args == [1]
    @test kwargs isa Vector{Pair{Symbol,Any}}
    @test isempty(kwargs)

    args, kwargs = Ray.recover_args([:x => 1])
    @test args isa Vector{Any}
    @test isempty(args)
    @test kwargs isa Vector{Pair{Symbol,Any}}
    @test kwargs == [:x => 1]

    args, kwargs = Ray.recover_args([Ray.ARG_KEY => 1, :x => 0x2])
    @test args isa Vector{Any}
    @test args == [1]
    @test kwargs isa Vector{Pair{Symbol,Any}}
    @test kwargs == [:x => 0x2]

    # order matters
    args, kwargs = Ray.recover_args([:x => 1, Ray.ARG_KEY => 0x2, :y => "3",
                                     Ray.ARG_KEY => 4.0])
    @test args isa Vector{Any}
    @test args == [0x2, 4.0]
    @test kwargs isa Vector{Pair{Symbol,Any}}
    @test kwargs == [:x => 1, :y => "3"]
end
