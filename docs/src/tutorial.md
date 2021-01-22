
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

There are several simplified functions to run parallel transformations of the
data and reductions:

- [`dtransform`](@ref) that processes all parts of dataset using a given
  function and stores the result
- [`dexec`](@ref) that is similar to `dtransform` but used to execute a
  function that works with the data using "side-effects" for increased
  efficiency, such as in case of the small array-modifying operations.
- [`dmapreduce`](@ref) that applies (maps) a function to all data parts and
  reduces (or folds) the results to one using another function
- [`dmap`](@ref) that executes a function over the distributed data parts,
  distributing a vector of values as parameters for that function.

For example, `dtransform` can be used to exponentiate the whole dataset:
```julia
julia> dataset = scatter_array(:myData, randn(1000,3), workers())
julia> get_val_from(dataset.workers[1], :(myData[1,:]))
3-element Array{Float64,1}:
 -1.0788051465727018
 -0.29710863020942757
 -2.5613834309426546

julia> dtransform(dataset, x -> 2 .^ x)
Dinfo(:myData, [2, 3, 4])

julia> get_val_from(dataset.workers[1], :(myData[1,:]))
3-element Array{Float64,1}:
 0.4734207525033287
 0.8138819001228813
 0.16941300928000705
```

You may have noticed that `dtransform` returns a new `Dinfo` object. That is
safe to ignore, but you can use `dtransform` to put the result into another
distributed variable with the extra argument, in which case the returned
`Dinfo` wraps this new distributed variable. That is very useful for easily
creating new datasets with the same command on all workers. In the following
example, also note that the function does not need to be quoted.

```julia
julia> anotherDataset = dtransform((), _ ->randn(100), workers(), :newData)
Dinfo(:newData, [2, 3, 4])
```

The `dexec` function is handy if your transformation does not modify the whole
array, but leaves most of it untouched and rewriting it would be a waste of
resources. This multiplies the 5-th element of each distributed array by 42:

```julia
julia> dexec(anotherDataset, arr -> arr[5] *= 42)
julia> gather_array(anotherDataset)[1:6]
6-element Array{Float64,1}:
  0.8270400003123709
 -0.10688512653581493
 -1.0462015551052068
 -1.2891453384843214
 16.429315504503112
  0.13958421716454797
  ⋮
```

MapReduce is a handy primitive that is suitable for operations that can
compress the dataset slices into relatively small values that can be combined
efficiently. For example, this computes the sum of squares of the whole array:

```julia
julia> dmapreduce(anotherDataset, x -> sum(x.^2), +)
8633.94032741762
```

Finally, `dmap` is useful for passing each worker a specific value from the
given vector, which may be useful in cases when each worker is supposed to do
something different with the data, such as submitting them to a different
interface or saving them as a different file. The results are returned as a
vector. This example is rather simplistic:

```julia
julia> dmap(Vector(1:length(workers())),
                   val -> "Worker number $(val) has ID $(myid())",
		   workers())
3-element Array{String,1}:
 "Worker number 1 has ID 2"
 "Worker number 2 has ID 3"
 "Worker number 3 has ID 4"
```

## Persisting the data

There some support for storing the loaded dataset on each worker's local
storage. This is quite beneficial for storing sub-results and various artifacts
for future use without wasting memory.

The available functions are:
- [`dstore`](@ref), which saves the dataset to a disk, such as in
```julia
julia> dstore(anotherDataset)
```
  ...which, in this case, creates files `newData-1.slice` to `newData-3.slice`
  that contain the respective parts of the dataset. The name can be modified
  using the `files` parameter.
- [`dload`](@ref), which loads the data back, using the same arguments as `dstore`
- [`dunlink`](@ref), which removes the corresponding files.

One possible use-case for this is a relatively easy way of data exchange
between nodes in a HPC environment, where the disk storage is usually a very
fast "scratch space" that is shared among all participants of a computation.

## Miscellaneous functions

There are many extra functions that work on matrix data, as common in many
science areas (especially in flow cytometry data processing, where DiDa
originated):

- [`dselect`](@ref) reduces a matrix to several selected columns
- [`dapply_cols`](@ref) transforms selected columns with a function
- [`dapply_rows`](@ref) does the same with rows
- [`dstat`](@ref) quickly computes mean and standard deviation in selected
  columns (as shown above)
- [`dstat_buckets`](@ref) does the same for multiple data "groups" present in
  the same matrix; the data groups are specified by an integer vector (this is
  great e.g. for computing per-cluster statistics, given the integer vector
  assigns data entries to clusters)
- [`dcount`](@ref) counts ocurrences of items in an integer vector, similar to
  e.g. R function `tabulate`
- [`dcount_buckets`](@ref) does the same per groups
- [`dscale`](@ref) scales the selected columns to mean 0 and standard deviation
  1
- [`dmedian`](@ref) computes a median in columns of the dataset (That is done
  by an approximative algorithm that works in time `O(n*iters)`, thus works
  even for really large datasets. Precision increases by roughly 1 bit per
  iteration, the default is 20 iterations.)
- [`dmedian_buckets`](@ref) computes the medians using the above method for
  multiple data groups
