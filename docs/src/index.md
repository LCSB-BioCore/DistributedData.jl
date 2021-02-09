
# DistributedData.jl — simple work with distributed data

This packages provides simple Distributed Data manipulation and processing
routines for Julia.

The design of the package and data manipulation approach is deliberately
"imperative" and "hands-on", to allow as much user influence on the actual way
the data are moved and stored in the cluster as possible. It is based on the
[`Distributed`](https://docs.julialang.org/en/v1/stdlib/Distributed/) package
and its infrastructure of remote workers. The basic `Distributed` package
functions `remotecall` and `fetch` are then wrapper (very lightly) to create a
simple yet powerful data manipulation interface.

There are also various extra functions to easily run distributed data
transformations, MapReduce-style algorithms, store and load the data remotely
on worker-local storage (e.g. to prevent memory exhaustion) and others.

To start quickly, you can read the tutorial:

```@contents
Pages=["tutorial.md", "slurm.md"]
```

### Functions

A full reference to all functions is given here:

```@contents
Pages = ["functions.md"]
```
