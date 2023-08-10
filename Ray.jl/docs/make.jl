using Ray
using Documenter

makedocs(; modules=[Ray],
         sitename="Ray.jl",
         authors="Beacon Biosignals",
         pages=["API Documentation" => "index.md"],
         strict=true)

deploydocs(; repo="github.com/beacon-biosignals/ray_core_worker_julia_jll.jl.git", push_preview=true,
           devbranch="main", dirname="Ray",
           versions=["stable" => "Ray-v^", "Ray-v#.#",
                     "dev" => "dev"])
