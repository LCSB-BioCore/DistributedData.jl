# <img src="docs/src/assets/logo.svg" alt="DistributedData.jl logo" height="32px"> DistributedData.jl


| Build status | Documentation |
|:---:|:---:|
| ![CI](https://github.com/LCSB-BioCore/DistributedData.jl/workflows/CI/badge.svg?branch=develop) | [![doc](https://img.shields.io/badge/docs-stable-blue)](https://lcsb-biocore.github.io/DistributedData.jl/stable/) [![doc](https://img.shields.io/badge/docs-dev-blue)](https://lcsb-biocore.github.io/DistributedData.jl/dev/) |

Simple distributed data manipulation and processing routines for Julia.

This was originally developed for
[`GigaSOM.jl`](https://github.com/LCSB-BioCore/GigaSOM.jl); DistributedData.jl package
contains the separated-out lightweight distributed-processing framework that
was used in `GigaSOM.jl`.

## Why?

DistributedData.jl provides a very simple, imperative and straightforward way to move your
data around a cluster of Julia processes created by the
[`Distributed`](https://docs.julialang.org/en/v1/stdlib/Distributed/) package,
and run computation on the distributed data pieces. The main aim of the package
is to avoid anything complicated-- the first version used in
[GigaSOM](https://github.com/LCSB-BioCore/GigaSOM.jl) had just under 500 lines
of relatively straightforward code (including the doc-comments).

Compared to plain `Distributed` API, you get more straightforward data
manipulation primitives, some extra control over the precise place where code
is executed, and a few high-level functions. These include a distributed
version of `mapreduce`, simpler work-alike of the
[DistributedArrays](https://github.com/JuliaParallel/DistributedArrays.jl)
functionality, and easy-to-use distributed dataset saving and loading.

Most importantly, the main motivation behind the package is that the
distributed processing should be simple and accessible.

## Brief how-to

The package provides a few very basic primitives that lightly wrap the
`Distributed` package functions `remotecall` and `fetch`. The most basic one is
`save_at`, which takes a worker ID, variable name and variable content, and
saves the content to the variable on the selected worker. `get_from` works the
same way, but takes the data back from the worker.

You can thus send some random array to a few distributed workers:

```julia
julia> using Distributed, DistributedData

julia> addprocs(2)
2-element Array{Int64,1}:
 2
 3

julia> @everywhere using DistributedData

julia> save_at(2, :x, randn(10,10))
Future(2, 1, 4, nothing)
```

The `Future` returned from `save_at` is the normal Julia future from
`Distributed`, you can even `fetch` it to wait until the operation is really
done on the other side. Fetching the data is done the same way:

```julia
julia> get_from(2,:x)
Future(2, 1, 15, nothing)

julia> get_val_from(2,:x) # auto-fetch()ing variant
10×10 Array{Float64,2}:
 -0.850788    0.946637     1.78006   … 
 -0.49596     0.497829    -2.03013
   …
```

All commands support full quoting, which allows you to easily distinguish
between code parts that are executed locally and remotely:

```julia
julia> save_at(3, :x, randn(1000,1000))     # generates a matrix locally and sends it to the remote worker

julia> save_at(3, :x, :(randn(1000,1000)))  # generates a matrix right on the remote worker and saves it there

julia> get_val_from(3, :x)                  # retrieves the generated matrix and fetches it
…

julia> get_val_from(3, :(randn(1000,1000))) # generates the matrix on the worker and fetches the data
…
```

Notably, this is different from the approach taken by `DistributedArrays` and
similar packages -- all data manipulation is explicit, and any data type is
supported as long as it can be moved among workers by the `Distributed`
package. This helps with various highly non-array-ish data, such as large text
corpora and graphs.

There are various goodies for easy work with matrix-style data, namely
scattering, gathering and running distributed algorithms:

```julia
julia> x = randn(1000,3)
1000×3 Array{Float64,2}:
 -0.992481   0.551064     1.67424
 -0.751304  -0.845055     0.105311
 -0.712687   0.165619    -0.469055
  ⋮

julia> dataset = scatter_array(:myDataset, x, workers())  # sends slices of the array to workers
Dinfo(:myDataset, [2, 3])   # a helper for holding the variable name and the used workers together

julia> get_val_from(3, :(size(myDataset)))
(500, 3)    # there's really only half of the data

julia> dmapreduce(dataset, sum, +) # MapReduce-style sum of all data
-51.64369103751014

julia> dstat(dataset, [1,2,3]) # get means and sdevs in individual columns
([-0.030724038974465212, 0.007300925745200863, -0.028220577808245786],
 [0.9917470012495775, 0.9975120525455358, 1.000243845434252])

julia> dmedian(dataset, [1,2,3]) # distributed iterative median in columns
3-element Array{Float64,1}:
  0.004742259615849834
  0.039043266340824986
 -0.05367799062404967

julia> dtransform(dataset, x -> 2 .^ x) # exponentiate all data (medians should now be around 1)
Dinfo(:myDataset, [2, 3])

julia> gather_array(dataset) # download the data from workers to a sing
1000×3 Array{Float64,2}:
 0.502613  1.46517   3.1915
 0.594066  0.55669   1.07573
 0.610183  1.12165   0.722438
  ⋮
```
