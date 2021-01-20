"""
    Dinfo

The basic structure for working with loaded data, distributed amongst workers. In completeness, it represents a dataset as such:

- `val` is the "value name" under which the data are saved in processes. E.g.
  `val=:foo` means that there is a variable `foo` on each process holding a
  part of the matrix.
- `workers` is a list of workers (in correct order!) that hold the data
  (similar to `DArray.pids`)
"""
struct Dinfo
    val::Symbol
    workers::Array{Int64}
    Dinfo(val, workers) = new(val, workers)
end
