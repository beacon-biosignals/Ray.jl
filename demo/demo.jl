using Ray
Ray.init()

return_ref = Ray.submit_task(max, (1, 2))
@show Ray.get(return_ref)
