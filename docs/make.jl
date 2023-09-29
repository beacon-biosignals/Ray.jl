using Ray
using Documenter

pages = ["API Documentation" => "index.md",
         "Installation" => "installation.md",
         "Developer Guide" => "developer-guide.md",
         "Building Artifacts" => "building-artifacts.md"]

makedocs(; modules=[Ray],
         format=Documenter.HTML(; prettyurls=get(ENV, "CI", nothing) == "true"),
         sitename="Ray.jl",
         authors="Beacon Biosignals",
         # Disable until we incorporate `ray_julia_jll/build/README.md` documentation here
         # linkcheck=true,
         pages)

deploydocs(; repo="github.com/beacon-biosignals/Ray.jl.git", push_preview=true,
           devbranch="main")
