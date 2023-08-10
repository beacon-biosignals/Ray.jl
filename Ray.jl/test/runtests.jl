using Test
using Ray
using Aqua

@testset "Ray.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(Ray; ambiguities=false)
    end

    

    # include additional test files here
end
