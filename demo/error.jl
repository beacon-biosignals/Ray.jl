using Ray

Ray.init()

entrypoint = function (x)
    function f(x)
        if x > 3
            throw(ErrorException("x > 3"))
        else
            Ray.get(Ray.submit_task(f, (x + 1,)))
        end
    end

    return f(x)
end

Ray.get(Ray.submit_task(entrypoint, (1,)))
