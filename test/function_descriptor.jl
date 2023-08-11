@testset "function descriptor" begin
    fd = function_descriptor(isless)

    @test fd isa JuliaFunctionDescriptor
    @test fd.module_name == "Base"
    @test fd.function_name == "isless"
    # hash may not be consistent across versions/environments
    @test fd.function_hash isa AbstractString
    @test length(fd.function_hash) == 16
    fd2 = function_descriptor(isless)
    @test fd2.function_hash == fd.function_hash
    # hash may not be consistent across versions/environments
    @test startswith(string(fd), "{type=JuliaFunctionDescriptor, module_name=Base, function_name=isless, function_hash=")

    fd = function_descriptor(M.f)
    @test fd.module_name == "Main.M"
    @test fd.function_name == "f"
end
