@testset "process_import_statements" begin
    @test Ray.process_import_statements(:(using Test)) == :(using Test)
    @test Ray.process_import_statements(:(using Test: @test)) == :(using Test: @test)
    @test Ray.process_import_statements(:(import Test)) == :(import Test)
    @test Ray.process_import_statements(:(import Test: @test)) == :(import Test: @test)
    @test Ray.process_import_statements(:(import Test as T)) == :(import Test as T)

    block = quote
        using Test
    end
    result = Ray.process_import_statements(block)
    @test result == Expr(:block, :(using Test))
    @test result != block  # LineNumberNode's have been stripped

    @test_throws ArgumentError Ray.process_import_statements(:(1 + 1))
    @test_throws ArgumentError Ray.process_import_statements(:(global foo = 1))
end

@testset "project_dir" begin
    result = Ray.project_dir()
    @test isdir(result)
    @test isabspath(result)
end
