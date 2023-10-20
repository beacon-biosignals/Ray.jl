# Using `collect` and `ncodeunits` to ensure that the entire string is captured and not just
# up to the first null character: https://github.com/JuliaInterop/CxxWrap.jl/pull/378
safe_convert(::Type{String}, str::StdString) = String(Vector{UInt8}(collect(str)))
safe_convert(::Type{StdString}, str::String) = StdString(str, ncodeunits(str))

safe_convert(::Type{String}, ref::ConstCxxRef{StdString}) = safe_convert(String, ref[])
