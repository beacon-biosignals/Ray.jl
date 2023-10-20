@testset "safe_convert" begin
    expected = "¿\0ÿ"
    cpp_expected = "Â¿\0Ã¿"

    std_str = Ray.safe_convert(StdString, expected)
    @test length(std_str) == length(cpp_expected)
    @test collect(std_str) == collect(cpp_expected)
    @test ncodeunits(std_str) == ncodeunits(expected)
    @test codeunits(std_str) == codeunits(expected)

    str = Ray.safe_convert(String, std_str)
    @test length(str) == length(expected)
    @test collect(str) == collect(expected)
    @test ncodeunits(str) == ncodeunits(expected)
    @test codeunits(str) == codeunits(expected)

    str = Ray.safe_convert(String, ConstCxxRef(std_str))
    @test length(str) == length(expected)
    @test collect(str) == collect(expected)
    @test ncodeunits(str) == ncodeunits(expected)
    @test codeunits(str) == codeunits(expected)
end
