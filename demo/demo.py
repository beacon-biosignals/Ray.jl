import ray

@ray.remote
def f(x):
    return x

local_ref = ray.put(1)
return_ref = f.remote(local_ref)
print(ray.get(return_ref))
