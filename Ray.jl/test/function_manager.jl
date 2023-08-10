using Ray: FunctionManager, export_function!, import_function!
using ray_core_worker_julia_jll: JuliaGcsClient, Connect, function_descriptor, JuliaFunctionDescriptor, Exists

client = JuliaGcsClient("127.0.0.1:6379")
Connect(client)

fm = FunctionManager(client, Dict{String,Any}())

jobid = 1337

f = x -> isless(x, 5)
export_function!(fm, f, jobid)

# XXX: this will segfault since the pointer is released...
fd = function_descriptor(f)
f2 = import_function!(fm, fd, jobid)

@test f2.(1:10) == f.(1:10)
