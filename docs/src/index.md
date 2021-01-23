
# DiDa.jl — simple work with distributed data

This packages provides a relatively simple Distributed Data manipulation and
processing routines for Julia.

The design of the package and data manipulation approach is deliberately
"imperative" and "hands-on", to allow as much user influence on the actual way
the data are moved and stored in the cluster as possible. It uses the
`Distributed` package and its infrastructure of workers, and provides a few
very basic primitives that lightly wrap the `Distributed` package functions
`remotecall` and `fetch`.

There are also various extra functions to easily run distributed data
transformations, MapReduce-style algorithms, store and load the data on worker
local storage (e.g. to prevent memory exhaustion) and others.

To start quickly, you can read the tutorial:

```@contents
Pages=["tutorial.md"]
```

### Functions

A full reference to all functions is given here:

```@contents
Pages = ["functions.md"]
```
