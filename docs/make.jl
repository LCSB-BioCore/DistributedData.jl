using Documenter, DistributedData

makedocs(modules = [DistributedData],
    clean = false,
    format = Documenter.HTML(prettyurls = !("local" in ARGS)),
    sitename = "DistributedData.jl",
    authors = "The developers of DistributedData.jl",
    linkcheck = !("skiplinks" in ARGS),
    pages = [
        "Documentation" => "index.md",
        "Tutorial" => "tutorial.md",
        "Function reference" => "functions.md",
    ],
)

deploydocs(
    repo = "github.com/LCSB-BioCore/DistributedData.jl.git",
    target = "build",
    branch = "gh-pages",
    devbranch = "develop",
    versions = "stable" => "v^",
)
