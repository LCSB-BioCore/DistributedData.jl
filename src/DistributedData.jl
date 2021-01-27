module DistributedData

using Distributed
using Serialization

include("structs.jl")
export Dinfo

include("base.jl")
export save_at,
    get_from,
    get_val_from,
    remove_from,
    scatter_array,
    unscatter,
    dexec,
    dtransform,
    dmapreduce,
    dmap,
    gather_array,
    tmp_symbol

include("io.jl")
export dstore,
    dload,
    dunlink

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
    dmedian,
    dmedian_buckets

end # module
