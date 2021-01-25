using Documenter, DiDa

makedocs(modules = [DiDa],
    clean = false,
    format = Documenter.HTML(prettyurls = !("local" in ARGS)),
    sitename = "DiDa.jl",
    authors = "The developers of DiDa.jl",
    linkcheck = !("skiplinks" in ARGS),
    pages = [
        "Documentation" => "index.md",
        "Tutorial" => "tutorial.md",
        "Function reference" => "functions.md",
    ],
)

deploydocs(
    repo = "github.com/LCSB-BioCore/DiDa.jl.git",
    target = "build",
    branch = "gh-pages",
    devbranch = "develop",
    versions = "stable" => "v^",
)
