import ray

@ray.remote
def f(x):
    if x > 3:
        raise Exception("x > 3")
    else:
        ray.get(f.remote(x + 1))

ray.get(f.remote(1))
