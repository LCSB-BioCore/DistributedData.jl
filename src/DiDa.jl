module DiDa

using Distributed
using Serialization

include("structs.jl")
export Dinfo

include("base.jl")
export save_at,
    get_from,
    get_val_from,
    remove_from,
    distribute_array,
    distribute_darray,
    undistribute,
    distributed_transform,
    distributed_mapreduce,
    distributed_foreach,
    distributed_collect

include("io.jl")
export distributed_export,
    distributed_import,
    distributed_unlink

include("tools.jl")
export dcopy,
    dselect,
    dapply_cols,
    dapply_rows,
    dstat,
    dstat_buckets,
    dcount,
    dcount_buckets,
    dscale,
    dtransform_asinh,
    dmedian,
    dmedian_buckets,
    mapbuckets,
    catmapbuckets

end # module
