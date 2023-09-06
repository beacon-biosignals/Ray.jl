# Use baremodule to shave off a few KB from the serialized `.ji` file
baremodule ray_julia_jll
using Base
using Base: UUID
import JLLWrappers
using Pkg

JLLWrappers.@generate_main_file_header("ray_julia")
JLLWrappers.@generate_main_file("ray_julia", UUID("c348cde4-7f22-4730-83d8-6959fb7a17ba"))

end  # module ray_julia_jll
