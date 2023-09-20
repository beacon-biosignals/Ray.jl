using Ray
import ray_julia_jll as ray_jll

# Show `RAY_*` environmental variables
for (k, v) in pairs(ENV)
    if startswith(k, "RAY_")
        println("$k=$(repr(v))")
    end
end
println()

Ray.init()

@show Ray.get_job_id()

@show Ray.get(Ray.submit_task(max, (1, 2)))

f = (x, y) -> max(x, y)
@show Ray.get(Ray.submit_task(f, (3, 4)))
