fd = function_descriptor(isless)

@test fd isa FunctionDescriptor
@test string(fd) == "{type=JuliaFunctionDescriptor, module_name=Base, function_name=isless, function_hash=}"
