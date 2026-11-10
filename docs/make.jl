using ModuleMixins
using Documenter
using DocumenterMermaid

DocMeta.setdocmeta!(ModuleMixins, :DocTestSetup, :(using ModuleMixins); recursive = true)

const page_rename = Dict("developer.md" => "Developer docs") # Without the numbers

makedocs(;
    modules = [ModuleMixins],
    authors = "Johan Hidding <j.hidding@esciencecenter.nl> and contributors",
    repo = "https://github.com/jhidding/ModuleMixins.jl/blob/{commit}{path}#{line}",
    sitename = "ModuleMixins.jl",
    format = Documenter.HTML(; canonical = "https://jhidding.github.io/ModuleMixins.jl"),
    pages = [
        "index.md",
        "15-tutorial.md",
        "16-tutorial-syntax.md",
        "41-composition.md",
        "42-composition-syntax.md",
        "90-contributing.md",
        "91-developer.md",
        "95-reference.md"
    ],
)

deploydocs(; repo = "github.com/jhidding/ModuleMixins.jl")
