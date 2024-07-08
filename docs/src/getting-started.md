# Getting Started

To get started with using Ray.jl you'll need to start by creating a Ray cluster. You can start by creating a local cluster by using:

```sh
ray start --head
```

After that you can run your Ray application in Julia. These applications start with the following commands to connect the Julia process to the Ray cluster:

```julia
using Ray
Ray.init()
```

A trivial Ray.jl application could look like:

```julia
using Ray
Ray.init()

# Define the square task.
square = x -> x * x

# Launch four parallel square tasks. Each task returns an object reference.
refs = [Ray.submit_task(square, (i,)) for i in 0:3]

# Retrieve results.
Ray.get.(refs)
# [0, 1, 4, 9]
```

Once you have finished running Ray applications you can shut down your cluster by using:

```sh
ray stop
```

## Further Reading

The [official Ray Core documentation](https://docs.ray.io/en/latest/ray-core/walkthrough.html) is a great resource for learning more about Ray. That documentation primarily provides Python examples which use a similar syntax to that of Ray.jl. Remember that `Actor`s are not yet supported in Ray.jl.
