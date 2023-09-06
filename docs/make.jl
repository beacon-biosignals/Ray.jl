using Ray
using Documenter

makedocs(; modules=[Ray],
         sitename="Ray.jl",
         authors="Beacon Biosignals",
         pages=["API Documentation" => "index.md"],
         strict=true)

deploydocs(; repo="github.com/beacon-biosignals/Ray.jl.git", push_preview=true,
           devbranch="main",
           versions=["stable" => "Ray-v^", "Ray-v#.#",
                     "dev" => "dev"])
