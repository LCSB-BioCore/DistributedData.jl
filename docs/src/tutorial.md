
# DistributedData tutorial

The primary purpose of this tutorial is to get a basic grasp of the main `DistributedData`
functions and methodology.

For starting up, let's create a few distributed workers and import the package:

```julia
julia> using Distributed, DistributedData

julia> addprocs(3)
2-element Array{Int64,1}:
 2
 3
 4

julia> @everywhere using DistributedData
```

## Moving the data around

In `DistributedData`, the storage of distributed data is done in the "native" Julia way --
the data is stored in normal named variables. Each node holds its own data in
an arbitrary set of variables as "plain data"; content of these variables is
completely independent among nodes.

There are two basic data-moving functions:

- [`save_at`](@ref), which evaluates a given expression on the remote worker,
  and stores it in a variable. In particular, `save_at(3, :x, 123)` is roughly
  the same as if you would manually connect to the Julia session on the worker
  `3` and type `x = 123`.
- [`get_from`](@ref), which evaluates a given object on the remote worker and
  returns a `Future` that holds the evaluated result. To get the value of `x`
  from worker `3`, you may call `fetch(get_from(3, :x))` to fetch the
  "contents" of that future. (Additionally, there is [`get_val_from`](@ref),
  which calls the `fetch` for you.)

The use of these functions is quite straightforward:

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

`DistributedData` uses *quoting* to allow you to precisely specify the parts of the code
that should be evaluated on the "main" Julia process (the one you interact
with), and the code that should be evaluated on the remote workers.  Basically,
all quoted code is going to get to the workers without any evaluation; all
other code is evaluated on the main node.

For example, this picks up the contents of variable `x` from the remote worker,
despite that actual symbol is named as `y` in the main process:
```julia
julia> y=:x
:x

julia> get_val_from(3, y)
123
```

This system is used to easily specify that some particular operations (e.g.,
heavy computations) are going to be executed on the remotes.

To illustrate the difference between quoted and non-quoted code, the following
code generates a huge random matrix locally and sends it to the worker, which
may not be desired (the data transfer takes a lot of precious time):

```julia
julia> save_at(2, :mtx, randn(1000, 1000))
```

On the remote worker `2`, this will be executed as something like
`mtx = [0.384478, 0.763806, -0.885208, …]` .

If you quote the parameter, it is not going to be evaluated on the main worker,
but rather goes unevaluated and "packed" as an expression to the remote, which
unpacks and evaluates it by itself:

```julia
julia> save_at(2, :mtx, :(randn(1000,1000)))
```

The data transfer is minimized to a few-byte expression `randn(1000,1000)`. On
the remote, this is executed properly as `mtx = randn(1000, 1000)`.

This is useful for handling large data -- you can easily load giant datasets to
the workers without hauling all the data through your computer; very likely
also decreasing the risk of out-of-memory problems.

The same principle applies for receiving the data -- you can let some of the workers
compute a very hard function and download it as follows:

```julia
julia> get_val_from(2, :( computeAnswerToMeaningOfLife() ))
42
```

If the expression in the previous case was not quoted, it would actually cause
the main worker to compute the answer, send it to worker `2`, and receive it
back unchanged, which is likely not what we wanted.

Finally, this way it is very easy to work with multiple variables saved at a single
worker -- you just reference them in the expression:
```julia
julia> save_at(2,:x,123)
julia> save_at(2,:y,321)
julia> get_val_from(2, :(2*x+y))
567
```

### Parallelization and synchronization

Operations executed by `save_at` and `get_from` are *asynchronous* by default,
which may be both good and bad, depending on the situation. For example, when
using `save_at`, the results of hard-to-compute functions may not yet be saved
at the time you need them. Let's demonstrate that on a "simulated" slow
function:

```julia
julia> save_at(2, :delayed, :(begin sleep(30); 42; end))
Future(2, 1, 18, nothing)

julia> get_val_from(2, :delayed)      # the computation is not finished yet, thus the variable is not assigned
ERROR: On worker 2:
UndefVarError: delayed not defined

# …wait 30 seconds…

julia> get_val_from(2, :delayed)
42
```

The simplest way to prevent such data races is to `fetch` the future returned
from `save_at`, which correctly waits until the result is properly available on
the target worker.

This *synchronization is not performed by default*, because the non-synchronized
behavior allows you to very easily implement parallelism. In particular, you
may start multiple asynchronous computations at once, and then wait for all of
them to complete to make sure all results are available. Because the operations
run asynchronously, they are processed concurrently, thus faster.

To illustrate the difference, the following code distributes some random data
and then synchronizes correctly, but is essentially serial:
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

The same is applicable for retrieving the sub-results in parallel. This example
demonstrates that multiple workers can do some work at the same time:

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
beneficial for implementing advanced parallel algorithms.

### `Dinfo` handles

Remembering and managing the remote variable names and worker numbers is
extremely impractical, especially if you need to maintain multiple variables on
various subsets of all available workers at once. `DistributedData` defines a small
[`Dinfo`](@ref) data structure that keeps that information for you. Many other
functions are able to work with `Dinfo` transparently, instead of the "raw"
symbols and worker lists.

For example, you can use [`scatter_array`](@ref) to automatically separate the
array-like dataset to roughly-same pieces scattered across multiple workers,
and obtain the `Dinfo` object:
```julia
julia> dataset = scatter_array(:myData, randn(1000,3), workers())
Dinfo(:myData, [2, 3, 4])
```

`Dinfo` contains the necessary information about the "contents" of the
distributed dataset: The name of variable used to save it on workers, and IDs
of individual workers. The storage of the variables is otherwise same as with
the basic data-moving function -- you can e.g. manually check the size of the
resulting slices on each worker using `get_from`:
```julia
julia> fetch.([get_from(w, :(size($(dataset.val)))) for w in dataset.workers])
3-element Array{Tuple{Int64,Int64},1}:
 (333, 3)
 (333, 3)
 (334, 3)
```
(Note the `$(...)` syntax for *un-quoting*, i.e., inserting evaluated data into
quoted expressions.)

The `Dinfo` object is used e.g. by the statistical functions, such as
[`dstat`](@ref) (see below for more examples). `dstat` just computes means and
standard deviations in selected columns of the data:

```julia
julia> dstat(dataset, [1,2])
([-0.029108965193981328, 0.019687519297162222],     # means
 [0.9923669075507301, 0.9768313338000191])          # sdevs
```

There are three functions for straightforward data management using the
`Dinfo`:

- [`dcopy`](@ref) for duplicating the data objects on all related workers
- [`unscatter`](@ref) for removing the data from workers (and freeing the
  memory)
- [`gather_array`](@ref) for collecting the array pieces from individual
  workers and pasting them together (an opposite of `scatter_array`)

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

There are several simplified functions to run parallel computation on the
distributed data:

- [`dtransform`](@ref) processes all worker's parts of the data using a given
  function and stores the result
- [`dmapreduce`](@ref) applies ("maps") a function to all data parts and
  reduces ("folds") the intermediate results to a single result using another
  function
- [`dexec`](@ref) is similar to `dtransform`, but expects a function that
  modifies the data in-place (using "side-effects"), for increased efficiency
  in cases such as very small array modifications
- [`dmap`](@ref) executes a function over the workers, also distributing a
  vector of values as parameters for that function.

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

You may have noticed that `dtransform` returns a new `Dinfo` object, which we
safely discard in this case. You can use `dtransform` to save the result into
another distributed variable (by supplying the new name in an extra argument),
in which case the returned `Dinfo` wraps this new distributed variable. That is
useful for easily generating new datasets on all workers, as in the following
example:

```julia
julia> anotherDataset = dtransform((), _ ->randn(100), workers(), :newData)
Dinfo(:newData, [2, 3, 4])
```

(Note that the function body does not need to be quoted.)

The `dexec` function is handy if your transformation does not modify the whole
array, but leaves most of it untouched and rewriting it would be a waste of
resources. This example multiplies the 5th element of each distributed array
part by 42:

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
"compress" the dataset slices into relatively small pieces of data, which can
be combined efficiently. For example, this computes the sum of squares of the
whole array:

```julia
julia> dmapreduce(anotherDataset, x -> sum(x.^2), +)
8633.94032741762
```

Finally, `dmap` passes each worker a specific value from a given vector, which
may be useful in cases when each worker is supposed to do something slightly
different with the data (for example, submit them to a different interface or
save them as a different file). The results are returned as a vector. This
example is rather simplistic:

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

`DistributedData` provides support for storing the loaded dataset in each worker's local
storage. This is quite beneficial for saving sub-results and various artifacts
of the computation process for later use, without unnecessarily wasting
main memory.

The available functions are as follows:
- [`dstore`](@ref) saves the dataset to a disk, such as in
  `dstore(anotherDataset)`, which, in this case, creates files
  `newData-1.slice` to `newData-3.slice` that contain the respective parts of
  the dataset. The precise naming scheme can be specified using the `files`
  parameter.
- [`dload`](@ref) loads the data back into memory (again using a `Dinfo`
  parameter with dataset description to get the dataset name and the list of
  relevant workers)
- [`dunlink`](@ref) removes the corresponding files from the storage

Apart from saving the data for later use, this provides a relatively easy way
to exchange the data among nodes in a HPC environment. There, the disk storage
is usually a very fast "scratch space" that is shared among all participants of
a computation, and can be used to "broadcast" or "shuffle" the data without any
significant overhead.

## Miscellaneous functions

For convenience, `DistributedData` also contains simple implementations of various common
utility operations for processing matrix data. These originated in
flow-cytometry use-cases (which is what `DistributedData` was originally built for), but
are applicable in many other areas of data analysis:

- [`dselect`](@ref) reduces a matrix to several selected columns (in a
  relatively usual scenario where the rows of the matrix are "events" and
  columns represent "features", `dselect` discards the unwanted features)
- [`dapply_cols`](@ref) transforms selected columns with a given function
- [`dapply_rows`](@ref) does the same with rows
- [`dstat`](@ref) quickly computes the mean and standard deviation in selected
  columns (as demonstrated above)
- [`dstat_buckets`](@ref) does the same for multiple data "groups" present in
  the same matrix, the data groups are specified by a distributed integer
  vector (This is useful e.g. for computing per-cluster statistics, in which
  case the integer vector should assign individual data entries to clusters.)
- [`dcount`](@ref) counts the numbers of occurrences of items in an integer
  vector, similar to e.g. R function `tabulate`
- [`dcount_buckets`](@ref) does the same per groups
- [`dscale`](@ref) scales the selected columns to mean 0 and standard deviation
  1
- [`dmedian`](@ref) computes a median of the selected columns of the dataset
  (The computation is done using an approximate iterative algorithm in time
  `O(n*iters)`, which scales even to really large datasets. The precision of
  the result increases by roughly 1 bit per iteration, the default is 20
  iterations.)
- [`dmedian_buckets`](@ref) uses the above method to compute the medians for
  multiple data groups
