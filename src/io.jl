
"""
    defaultFiles(s, pids)

Make a good set of filenames for saving a dataset.
"""
function defaultFiles(s, pids)
    return [String(s) * "-$i.slice" for i in eachindex(pids)]
end

"""
    dstore(sym::Symbol, pids, files=defaultFiles(sym,pids))

Export the content of symbol `sym` by each worker specified by `pids` to a
corresponding filename in `files`.
"""
function dstore(sym::Symbol, pids, files = defaultFiles(sym, pids))
    dmap(
        files,
        (fn) -> Base.eval(Main, :(
            begin
                open(f -> $serialize(f, $sym), $fn, "w")
                nothing
            end
        )),
        pids,
    )
    nothing
end

"""
    dstore(dInfo::Dinfo, files=defaultFiles(dInfo.val, dInfo.workers))

Overloaded functionality for `Dinfo`.
"""
function dstore(dInfo::Dinfo, files = defaultFiles(dInfo.val, dInfo.workers))
    dstore(dInfo.val, dInfo.workers, files)
end

"""
    dload(sym::Symbol, pids, files=defaultFiles(sym,pids))

Import the content of symbol `sym` by each worker specified by `pids` from the
corresponding filename in `files`.
"""
function dload(sym::Symbol, pids, files = defaultFiles(sym, pids))
    dmap(files, (fn) -> Base.eval(Main, :(
        begin
            $sym = open($deserialize, $fn)
            nothing
        end
    )), pids)
    return Dinfo(sym, pids)
end

"""
    dload(dInfo::Dinfo, files=defaultFiles(dInfo.val, dInfo.workers))

Overloaded functionality for `Dinfo`.
"""
function dload(dInfo::Dinfo, files = defaultFiles(dInfo.val, dInfo.workers))
    dload(dInfo.val, dInfo.workers, files)
end

"""
    dunlink(sym::Symbol, pids, files=defaultFiles(sym,pids))

Remove the files created by `dstore` with the same parameters.
"""
function dunlink(sym::Symbol, pids, files = defaultFiles(sym, pids))
    dmap(files, (fn) -> rm(fn), pids)
    nothing
end

"""
    dunlink(dInfo::Dinfo, files=defaultFiles(dInfo.val, dInfo.workers))

Overloaded functionality for `Dinfo`.
"""
function dunlink(dInfo::Dinfo, files = defaultFiles(dInfo.val, dInfo.workers))
    dunlink(dInfo.val, dInfo.workers, files)
end
