using Ray
using Documenter

makedocs(; modules=[Ray],
         sitename="Ray.jl",
         authors="Beacon Biosignals",
         pages=["API Documentation" => "index.md"],
         strict=true)

# TODO: swap when we move to own repo
# deploydocs(; repo="github.com/beacon-biosignals/Ray.jl.git", push_preview=true,
#            devbranch="main",
#            versions=["stable" => "v^", "v#.#",
#                      "dev" => "dev"])

deploydocs(; repo="github.com/beacon-biosignals/ray_core_worker_julia_jll.jl.git", push_preview=true,
           devbranch="main", dirname="Ray",
           versions=["stable" => "Ray-v^", "Ray-v#.#",
                     "dev" => "dev"])
