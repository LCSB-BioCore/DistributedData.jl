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
