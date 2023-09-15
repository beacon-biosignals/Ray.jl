using Ray
Ray.init()

return_ref = Ray.submit_task(sum, (1, 1))
@show Ray.get(return_ref)
