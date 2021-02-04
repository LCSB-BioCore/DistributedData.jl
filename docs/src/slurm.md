
# DistributedData.jl on Slurm clusters

DistributedData scales well to moderately large computer clusters. As a
practical example, you can see the script that was used to process relatively
large datasets for GigaSOM, documented in the Supplementary file of the
[GigaSOM
article](https://academic.oup.com/gigascience/article/9/11/giaa127/5987271)
(click the `giaa127_Supplemental_File` link below on the page, and find
*Listing S1* at the end of the PDF).

Use of DistributedData with [Slurm](https://slurm.schedmd.com/overview.html) is
similar as with many other distributed computing systems:

1. You submit a batch (or interactive) task, which runs your Julia script on a
   node and gives it some information about where to find other worker nodes.
2. In the Julia script, you use
   [`ClusterManagers`](https://github.com/JuliaParallel/ClusterManagers.jl)
   function `addprocs_slurm` to add the processes, just as with normal
   `addprocs`. Similar functions exist for many other task schedulers,
   including the popular PBS and LSF.
3. The rest of the workflow is unchanged; all functions from `DistributedData`
   such as `save_at` and `dmapreduce` will work in the cluster just as they
   worked locally. Performance will vary though -- you may want to optimize
   your algorithm to use as much parallelism as possible (to get lots of
   performance), load more data in the memory (usually, much more total memory
   is available in the clusters than on a single computer), but keep an eye on
   the communication overhead, transferring only the minimal required amount of
   data as seldom as possible.

An example Slurm batch script is here, save it as `run-analysis.batch` to your
Slurm gateway machine, in a directory that is shared with the workers (usually
a subdirectory of `/scratch`):
```sh
#!/bin/bash -l
#SBATCH -n 128
#SBATCH -c 1
#SBATCH -t 60
#SBATCH --mem-per-cpu 4G
#SBATCH -J MyDistributedJob

module load lang/Julia/1.3.0

julia run-analysis.jl
```

The parameters are, in order:
- using 128 "tasks" (ie. spawning 128 separate processes)
- each process uses 1 CPU (you may want more CPUs if you work with actual
  threads and shared memory)
- the whole batch takes maximum 60 minutes
- each CPU (in our case each process) will be allocated 4 gigabytes of RAM
- the job will be visible in the queue as `MyDistributedJob`
- it will load Julia 1.3.0 module on the workers, so that `julia` executable is
  available (you may want to consult the versions availability with your HPC
  administrators)
- finally, it will run the Julia script `run-analysis.jl`

The `run-analysis.jl` may look as follows:
```julia
using  Distributed, ClusterManagers, DistributedData

# read the number of available workers from  environment and start the worker processes

n_workers = parse(Int , ENV["SLURM_NTASKS"])
addprocs_slurm(n_workers , topology =:master_worker)

# load the required packages on all workers
@everywhere using DistributedData

# generate a random dataset on all workers
dataset = dtransform((), _ -> randn(10000,10000), workers(), :myData)

# for demonstration, sum the whole dataset
totalResult = dmapreduce(dataset, sum, +)

# do not forget to save the results!
f = open("result.txt", "w")
println(f, totalResult)
close(f)
```

Finally, you can execute the whole thing with `sbatch`:
```sh
sbatch run-analysis.batch
```

After your tasks gets queued, executed and finished successfully, you may see
the result in `result.txt`. In the meantime, you can entertain yourself by
watching `squeue`, to see e.g. the expected execution time of your batch.
