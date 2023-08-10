# export ray_core_worker_julia
export Language, WorkerType

using CxxWrap
using libcxxwrap_julia_jll

using Serialization

JLLWrappers.@generate_wrapper_header("ray_core_worker_julia")
JLLWrappers.@declare_library_product(ray_core_worker_julia, "julia_core_worker_lib.so")
@wrapmodule(joinpath(artifact"ray_core_worker_julia", "julia_core_worker_lib.so"))

function __init__()
    JLLWrappers.@generate_init_header(libcxxwrap_julia_jll)
    JLLWrappers.@init_library_product(
        ray_core_worker_julia,
        "julia_core_worker_lib.so",
        RTLD_GLOBAL,
    )

    JLLWrappers.@generate_init_footer()
    @initcxx
end  # __init__()

function node_manager_port()
    line = open("/tmp/ray/session_latest/logs/raylet.out") do io
        while !eof(io)
            line = readline(io)
            if contains(line, "NodeManager server started")
                return line
            end
        end
    end

    m = match(r"port (\d+)", line)
    return m !== nothing ? parse(Int, m[1]) : error("Unable to find port")
end

initialize_coreworker() = initialize_coreworker(node_manager_port())

# function Base.Symbol(language::Language)
#     return if language === PYTHON
#         :PYTHON
#     elseif field === JAVA
#         :JAVA
#     elseif field === CPP
#         :CPP
#     elseif field === JULIA
#         :JULIA
#     else
#         throw(ArgumentError("Unknown language: $language"))
#     end
# end

# Base.instances(::Type{Language}) = (PYTHON, JAVA, CPP, JULIA)

function Base.getproperty(::Type{Language}, field::Symbol)
    return if field === :PYTHON
        PYTHON
    elseif field === :JAVA
        JAVA
    elseif field === :CPP
        CPP
    elseif field === :JULIA
        JULIA
    else
        Base.getfield(Language, field)
    end
end

function Base.propertynames(::Type{Language}, private::Bool=false)
    public_properties = (:PYTHON, :JAVA, :CPP, :JULIA)
    return if private
        tuple(public_properties..., fieldnames(typeof(Language))...)
    else
        public_properties
    end
end

function Base.getproperty(::Type{WorkerType}, field::Symbol)
    return if field === :WORKER
        WORKER
    elseif field === :DRIVER
        DRIVER
    elseif field === :SPILL_WORKER
        SPILL_WORKER
    elseif field === :RESTORE_WORKER
        RESTORE_WORKER
    else
        Base.getfield(WorkerType, field)
    end
end

function Base.propertynames(::Type{WorkerType}, private::Bool=false)
    public_properties = (:WORKER, :DRIVER, :SPILL_WORKER, :RESTORE_WORKER)
    return if private
        tuple(public_properties..., fieldnames(typeof(WorkerType))...)
    else
        public_properties
    end
end

#####
##### Function descriptor wrangling
#####

# build a FunctionDescriptor from a julia function
function function_descriptor(f::Function)
    mod = string(parentmodule(f))
    name = string(nameof(f))
    hash = let io = IOBuffer()
        serialize(io, f)
        # hexidecimal string repr of hash
        string(Base.hash(io.data); base=16)
    end
    return function_descriptor(mod, name, hash)
end

Base.show(io::IO, fd::FunctionDescriptor) = print(io, ToString(fd))
Base.show(io::IO, fd::JuliaFunctionDescriptor) = print(io, ToString(fd))
function Base.propertynames(fd::JuliaFunctionDescriptor, private::Bool=false)
    public_properties = (:module_name, :function_name, :function_hash)
    return if private
        tuple(public_properties..., fieldnames(typeof(fd))...)
    else
        public_properties
    end
end

# JuliaFunctionDescriptor(fd::FunctionDescriptor) = GimmeJuliaFunction(fd)[]
# Base.convert(::Type{JuliaFunctionDescriptor}, fd::FunctionDescriptor) = JuliaFunctionDescriptor(fd)

function Base.getproperty(fd::JuliaFunctionDescriptor, field::Symbol)
    return if field === :module_name
        # these return refs so we need to de-reference them
        ModuleName(fd)[]
    elseif field === :function_name
        FunctionName(fd)[]
    elseif field === :function_hash
        FunctionHash(fd)[]
    else
        Base.getfield(fd, field)
    end
end

Base.show(io::IO, status::Status) = print(io, ToString(status))

#####
##### Upstream fixes
#####

# Works around what appears to be a CxxWrap issue
function put(buffer::CxxWrap.StdLib.SharedPtr{LocalMemoryBuffer})
    return put(CxxWrap.CxxWrapCore.__cxxwrap_smartptr_cast_to_base(buffer))
end
