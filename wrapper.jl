module Wrapper

using CxxWrap
using Pkg.Artifacts
using ray_core_worker_julia_jll

path = artifact"ray_core_worker_julia"
@wrapmodule("$path/lib/julia_core_worker_lib.so")

function __init__()
    @initcxx
end

end

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

@show Wrapper.put_get("Greetings from Julia!", node_manager_port())
