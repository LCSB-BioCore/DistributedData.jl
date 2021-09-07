using Documenter, DistributedData

makedocs(
    modules = [DistributedData],
    clean = false,
    format = Documenter.HTML(
        prettyurls = !("local" in ARGS),
        canonical = "https://lcsb-biocore.github.io/DistributedData.jl/stable/",
        assets = ["assets/logo.ico"],
    ),
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
    push_preview = true,
)
