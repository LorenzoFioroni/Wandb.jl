using WandbLogger
using Documenter

DocMeta.setdocmeta!(WandbLogger, :DocTestSetup, :(using WandbLogger); recursive=true)

makedocs(;
    modules=[WandbLogger],
    authors="Lorenzo Fioroni <lor.fioroni@gmail.com>",
    sitename="WandbLogger.jl",
    format=Documenter.HTML(;
        canonical="https://LorenzoFioroni.github.io/WandbLogger.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/LorenzoFioroni/WandbLogger.jl",
    devbranch="main",
)
