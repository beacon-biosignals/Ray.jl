# Ray.jl

[![CI](https://github.com/beacon-biosignals/Ray.jl/workflows/CI/badge.svg?branch=main)](https://github.com/beacon-biosignals/Ray.jl/actions/workflows/CI.yml?query=workflow%3ACI+branch%3Amain)
[![codecov](https://codecov.io/gh/beacon-biosignals/Ray.jl/graph/badge.svg)](https://codecov.io/gh/beacon-biosignals/Ray.jl)

The Ray.jl provides a Julia language interface for [Ray.io](https://www.ray.io/) workloads.

## FAQ

### How do I start/stop the ray backend?

Make sure the appropriate Python environment (i.e. `source venv/bin/activate`) is active (wherever you [`pip install`ed the Ray CLI](./docs/src/installation.md)) and then do:

```sh
ray start --head
```

to start and

```sh
ray stop
```

to stop.

### Where can I find log files?

The directory `/tmp/ray/session_latest/logs` contains logs for the current or last ran ray backend.

The `raylet.err` is particularly informative when debugging workers failing to start, since error output before connecting to the Ray server is printed there.

Driver logs generated by Ray are printed in `julia-core-driver-$(JOBID)_$(PID).log`, and julia worker logs are in `julia_worker_$(PID).log` (although this may change).

### My workers aren't starting, help?

Check the raylet logs in `/tmp/ray/session_latest/logs/raylet.err`.  If you see something about Revise (or another package) not being found, make sure you're not doing something like unconditionally `using Revise` in your `~/.julia/config/startup.jl` file; it's generally a good idea to wrap any `using`s in your startup.jl in a `try`/`catch` block [like the Revise docs recommend](https://timholy.github.io/Revise.jl/stable/config/#Using-Revise-by-default-1).
