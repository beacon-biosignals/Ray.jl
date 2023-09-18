# https://docs.ray.io/en/latest/ray-core/patterns/nested-tasks.html
using Ray
using Random

Ray.init()


function partition(collection::AbstractVector{T}) where T
    # Use the last element as the pivot
    pivot = pop!(collection)
    greater, lesser = T[], T[]
    for element in collection
        if element > pivot
            append!(greater, element)
        else
            append!(lesser, element)
        end
    end
    return lesser, pivot, greater
end

function quick_sort(collection)
    if length(collection) <= 200000  # magic number
        return sort!(collection)
    else
        lesser, pivot, greater = partition(collection)
        lesser = quick_sort(lesser)
        greater = quick_sort(greater)
    end
    return [lesser; pivot; greater]
end


quick_sort_distributed_anon = function (collection)
    function partition(collection::AbstractVector{T}) where T
        # Use the last element as the pivot
        pivot = pop!(collection)
        greater, lesser = T[], T[]
        for element in collection
            if element > pivot
                append!(greater, element)
            else
                append!(lesser, element)
            end
        end
        return lesser, pivot, greater
    end

    function quick_sort_distributed(collection)
        # Tiny tasks are an antipattern.
        # Thus, in our example we have a "magic number" to
        # toggle when distributed recursion should be used vs
        # when the sorting should be done in place. The rule
        # of thumb is that the duration of an individual task
        # should be at least 1 second.
        if length(collection) <= 200000  # magic number
            return sort!(collection)
        else
            lesser, pivot, greater = partition(collection)
            lesser = Ray.submit_task(quick_sort_distributed, (lesser,); resources=Dict("CPU" => 0.01))
            greater = Ray.submit_task(quick_sort_distributed, (greater,); resources=Dict("CPU" => 0.01))
            return [Ray.get(lesser); pivot; Ray.get(greater)]
        end
    end

    return quick_sort_distributed(collection)
end


for len in (200000, 4000000, 8000000)
    println("Array length: $(len)")
    unsorted = rand(Int, len)
    s = time()
    quick_sort(unsorted)
    println("Sequential execution: $(time() - s)")
    s = time()
    Ray.get(Ray.submit_task(quick_sort_distributed_anon, (unsorted,); resources=Dict("CPU" => 0.01)))
    println("Distributed execution: $(time() - s)")
    println("--" ^ 10)
end
