
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

1. You install Julia and the required packages.
2. You submit a batch (or interactive) task, which runs your Julia script on a
   node and gives it some information about where to find other worker nodes.
3. In the Julia script, you use
   [`ClusterManagers`](https://github.com/JuliaParallel/ClusterManagers.jl)
   function `addprocs_slurm` to add the processes, just as with normal
   `addprocs`. Similar functions exist for many other task schedulers,
   including the popular PBS and LSF.
4. The rest of the workflow is unchanged; all functions from `DistributedData`
   such as `save_at` and `dmapreduce` will work in the cluster just as they
   worked locally. Performance will vary though -- you may want to optimize
   your algorithm to use as much parallelism as possible (to get lots of
   performance), load more data in the memory (usually, much more total memory
   is available in the clusters than on a single computer), but keep an eye on
   the communication overhead, transferring only the minimal required amount of
   data as seldom as possible.

### Preparing the packages

The easiest way to install the packages is using a single-machine interactive
job. On the access node of your HPC, run this command to give you a 60-minute
interactive session:
```sh
srun --pty -t60 /bin/bash -
```

(Depending on your cluster setup, it may be benerifical to also specify a
partition to which the job should belong to; many clusters provide an
interactive partition where the interactive jobs get scheduled faster. To do
that, add option `-p interactive` into the parameters of `srun`.)

When the shell opens (the prompt should change), you can load the Julia module,
usually with a command such as this:

```sh
module load lang/Julia/1.3.0
```

(You may consult `module spider julia` for other possible Julia versions.)

After that, start `julia` and add press `]` to open the packaging prompt (you
should see `(v1.3) pkg>` instead of `julia>`). There you can download and
install the required packages:
```
add DistributedData, ClusterManagers
```

You may also want to load the packages to precompile them, which saves precious
time later in the workflows. Press backspace to return to the "normal" Julia
shell, and type:
```julia
using DistributedData, ClusterManagers
```

Depending on the package, this may take a while, but should be done in under a
minute for most existing packages. Finally, press `Ctrl+D` twice to exit both
Julia and the interactive Slurm job shell.

### Slurm batch script

An example Slurm batch script
([download](https://github.com/LCSB-BioCore/DistributedData.jl/blob/master/docs/slurm-example/run-analysis.batch))
is listed below -- save it as `run-analysis.batch` to your Slurm access node,
in a directory that is shared with the workers (usually a "scratch" directory;
try `cd $SCRATCH`).
```sh
#!/bin/bash -l
#SBATCH -n 128
#SBATCH -c 1
#SBATCH -t 10
#SBATCH --mem-per-cpu 4G
#SBATCH -J MyDistributedJob

module load lang/Julia/1.3.0

julia run-analysis.jl
```

The parameters in the script have this meaning, in order:
- the batch spawns 128 "tasks" (ie. spawning 128 separate processes)
- each task uses 1 CPU (you may want more CPUs if you work with actual
  threads and shared memory)
- the whole batch takes maximum 10 minutes
- each CPU (in our case each process) will be allocated 4 gigabytes of RAM
- the job will be visible in the queue as `MyDistributedJob`
- it will load Julia 1.3.0 module on the workers, so that `julia` executable is
  available (you may want to consult the versions availability with your HPC
  administrators)
- finally, it will run the Julia script `run-analysis.jl`

### Julia script

The `run-analysis.jl`
([download](https://github.com/LCSB-BioCore/DistributedData.jl/blob/master/docs/slurm-example/run-analysis.jl))
may look as follows:
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

Finally, you can start the whole thing with `sbatch` command executed on the
access node:
```sh
sbatch run-analysis.batch
```

### Collecting the results

After your tasks gets queued, executed and finished successfully, you may see
the result in `result.txt`. In the meantime, you can entertain yourself by
watching `squeue`, to see e.g. the expected execution time of your batch.

Note that you may want to run the analysis in a separate directory, because the
logs from all workers are collected in the current path by default. The
resulting files may look like this:
```
0 [user@access1 test]$ ls
job0000.out  job0019.out  job0038.out  job0057.out  job0076.out  job0095.out  job0114.out
job0001.out  job0020.out  job0039.out  job0058.out  job0077.out  job0096.out  job0115.out
job0002.out  job0021.out  job0040.out  job0059.out  job0078.out  job0097.out  job0116.out
job0003.out  job0022.out  job0041.out  job0060.out  job0079.out  job0098.out  job0117.out
job0004.out  job0023.out  job0042.out  job0061.out  job0080.out  job0099.out  job0118.out
job0005.out  job0024.out  job0043.out  job0062.out  job0081.out  job0100.out  job0119.out
job0006.out  job0025.out  job0044.out  job0063.out  job0082.out  job0101.out  job0120.out
job0007.out  job0026.out  job0045.out  job0064.out  job0083.out  job0102.out  job0121.out
job0008.out  job0027.out  job0046.out  job0065.out  job0084.out  job0103.out  job0122.out
job0009.out  job0028.out  job0047.out  job0066.out  job0085.out  job0104.out  job0123.out
job0010.out  job0029.out  job0048.out  job0067.out  job0086.out  job0105.out  job0124.out
job0011.out  job0030.out  job0049.out  job0068.out  job0087.out  job0106.out  job0125.out
job0012.out  job0031.out  job0050.out  job0069.out  job0088.out  job0107.out  job0126.out
job0013.out  job0032.out  job0051.out  job0070.out  job0089.out  job0108.out  job0127.out
job0014.out  job0033.out  job0052.out  job0071.out  job0090.out  job0109.out  result.txt        <-- here is the result!
job0015.out  job0034.out  job0053.out  job0072.out  job0091.out  job0110.out  run-analysis.jl
job0016.out  job0035.out  job0054.out  job0073.out  job0092.out  job0111.out  run-analysis.sbatch
job0017.out  job0036.out  job0055.out  job0074.out  job0093.out  job0112.out  slurm-2237171.out
job0018.out  job0037.out  job0056.out  job0075.out  job0094.out  job0113.out
```

The files `job*.out` contain the information collected from individual
workers' standard outputs, such as the output of `println` or `@info`. For
complicated programs, this is the easiest way to get out the debugging
information, and a simple but often sufficient way to collect benchmarking
output (using e.g. `@time`).
