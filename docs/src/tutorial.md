
# DiDa tutorial

The primary purpose of this tutorial is to get a basic grasp of the main `DiDa`
functions and methodology.

For starting up, let's create a few distributed workers and import the package:

```julia
julia> using Distributed, DiDa

julia> addprocs(3)
2-element Array{Int64,1}:
 2
 3
 4

julia> @everywhere using DiDa
```

## Moving the data around

In `DiDa`, the storage of distributed data is done in the "native" Julia way --
the data is stored in normal named variables. Each node holds its own dataset
in a custom set of variables, and these are completely independent of each
other.

There are two basic data-moving functions:

- [`save_at`](@ref), which evaluates a given object on the remote worker, and
  stores it in a variable. `save_at(3, :x, 123)` is roughly the same as if you
  connected to the Julia session on the worker `3` and typed `x = 123`.
- [`get_from`](@ref), which evaluates a given object on the remote worker and
  returns a `Future` that holds the evaluated result. To get the value of `x`
  from worker `3`, you call `fetch(get_from(3, :x))`.

Additionally, there is [`get_val_from`](@ref), which calls the `fetch` right
away.

```julia
julia> save_at(3,:x,123)
Future(3, 1, 11, nothing)

julia> get_val_from(3, :x)
123

julia> get_val_from(4, :x)
ERROR: On worker 4:
UndefValError: x not defined
…
```

We use quoting to precisely distinguish what code is evaluated on the "leader"
worker that you use, and what code is evaluated on the workers. Basically,
everything quoted is going to get to the workers without any evaluation;
everything other is evaluated on the main node.

For example, this picks up variable `x` from the node, which is named as `y` on
the main node:
```julia
julia> y=:x
:x

julia> get_val_from(3, y)
123
```

The quoting system can be easily exploited to tell the system that some
operations (e.g., heavy computations) are going to be executed on the remotes.

For example, this code generates a huge random matrix locally and sends it to
the worker, which may not be desired (the data transfer takes precious time):

```julia
julia> save_at(2, :mtx, randn(1000, 1000))
```

On the remote, this may have been executed as something like
`mtx = [0.384478, 0.763806, -0.885208, …]` .

If you quote the parameter, it is not going to be evaluated on the main worker,
but rather goes unevaluated and "packed" as an expression to the remote, which
unpacks and evaluates it for itself. The data transfer is thus minimized:

```julia
julia> save_at(2, :mtx, :(randn(1000,1000)))
```

On the remote, this is executed properly as `mtx = randn(1000, 1000)`. This is
useful if handling large data -- you can easily load giant datasets to the
workers without the risk that all data are loaded at your computer, likely
causing an out-of-memory trouble.

The same applies for receiving the data -- you can let some of the workers
compute a very hard function and download it as follows:

```julia
julia> get_val_from(2, :( computeAnswerToMeaningOfLife() ))
42
```

If the expression in the previous case was not quoted, it would actually lead
to the main worker computing the answer, sending it to worker `2`, and
receiving back, which is likely not what we wanted.

Finally, it is very easy to work with multiple variables saved at a single
worker -- you just reference them in the expression:
```julia
julia> save_at(2,:x,123)
julia> save_at(2,:y,321)
julia> get_val_from(2, :(2*x+y))
567
```

### Parallelization and synchronization

Operations executed by `save_at` and `get_from` are asynchronous by default,
which is good and bad, depending on the purpose. For example, results of
hard-to-compute functions may not yet be saved at the time you need them. Let's
demonstrate that on a simulated-hard function:

```julia
julia> save_at(2, :delayed, :(begin sleep(30); 42; end))
Future(2, 1, 18, nothing)

julia> get_val_from(2, :delayed)
ERROR: On worker 2:
UndefVarError: delayed not defined

# …wait 30 seconds…

julia> get_val_from(2, :delayed)
42
```

The simplest way to prevent such data races is to `fetch` the future returned
from `save_at`, which correctly waits until the result is available.

The synchronization is not performed by default because the non-syncronized
behavior allows to very easily implement parallelism -- you can start multiple
computations at once, and then wait for all of them to complete.

For example, this code distributes the random data and synchronizes correctly,
but is basically serial:
```julia
julia> @time for i in workers()
         fetch(save_at(i, :x, :(randn(10000,10000))))
       end
  1.073267 seconds (346 allocations: 12.391 KiB)
```

By spawning the operations first and waiting for all of them later, you can
make the code parallel, and usually a few times faster (depending on the number
of workers):

```julia
julia> @time fetch.([save_at(i, :x, :(randn(10000,10000))) for i in workers()])
  0.403235 seconds (44.50 k allocations: 2.277 MiB)
3-element Array{Nothing,1}:
nothing
…
```

The same is applicable for retrieving the sub-results parallely. This example
demonstrates that multiple workers do some work (in this case, wait actively)
at the same time:

```julia
julia> @time fetch.([get_from(i, :(begin sleep(1); myid(); end))
                     for i in workers()])
  1.027651 seconds (42.26 k allocations: 2.160 MiB)
3-element Array{Int64,1}:
 2
 3
 4
```

Notably, you can even send individual `Future`s to other workers, allowing the
workers to synchronize and transfer the data among each other. This is
beneficial for implementing advanced parallel algoritms.

### `Dinfo` handles

Remembering the remote variable names and worker numbers is extremely
impractical, especially if you manage multiple variables on various subsets of
all available workers at once. `DiDa` defines a small [`Dinfo`](@ref) data structure
that manages exactly that information for you. Many other functions are able to
work with `Dinfo` transparently, instead of the "raw" identifiers and worker
lists.

For example, you can use [`scatter_array`](@ref) to automatically separate the
array-like dataset to roughly-same pieces scattered accross multiple workers,
and obtain the `Dinfo` object:
```julia
julia> dataset = scatter_array(:myData, randn(1000,3), workers())
Dinfo(:myData, [2, 3, 4])
```

You can check the size of the resulting slices on each worker (note the
`$(...)` syntax for un-quoting, i.e., inserting evaluated data into quoted
expressions):
```julia
julia> fetch.([get_from(w, :(size($(dataset.val)))) for w in dataset.workers])
3-element Array{Tuple{Int64,Int64},1}:
 (333, 3)
 (333, 3)
 (334, 3)
```

The `Dinfo` object is used e.g. by the statistical functions, such as
[`dstat`](@ref) (see below for more examples). `dstat` just computes means and
standard deviations in selected columns of the data:

```julia
julia> dstat(dataset, [1,2])
([-0.029108965193981328, 0.019687519297162222],     # means
 [0.9923669075507301, 0.9768313338000191])          # sdevs
```

There are three functions for basic dataset management using the `Dinfo`:

- [`dcopy`](@ref) for duplicating the data objects on all related workers
- [`unscatter`](@ref) for removing the data from workers (and freeing the
  memory)
- [`gather_array`](@ref) for collecting the array pieces from individual
  workers and pasting them together (an opposite of `scatter_array`.

Continuing the previous example, we can copy the data, remove the originals,
and gather the copies:

```julia
julia> dataset2 = dcopy(dataset, :backup)
Dinfo(:backup, [2, 3, 4])

julia> unscatter(dataset)

julia> get_val_from(2, :myData)
 # nothing

julia> gather_array(dataset2)
1000×3 Array{Float64,2}:
  0.241102   0.62638     0.759203
  0.981085  -1.01467    -0.495331
 -0.439979  -0.884943   -1.62218
  ⋮
```

## Transformations and reductions

## Persisting the data

## Miscellaneous functions

