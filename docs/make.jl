using ModuleMixins
using Documenter

DocMeta.setdocmeta!(ModuleMixins, :DocTestSetup, :(using ModuleMixins); recursive = true)

const page_rename = Dict("developer.md" => "Developer docs") # Without the numbers

makedocs(;
  modules = [ModuleMixins],
  authors = "Johan Hidding <j.hidding@esciencecenter.nl> and contributors",
  repo = "https://github.com/jhidding/ModuleMixins.jl/blob/{commit}{path}#{line}",
  sitename = "ModuleMixins.jl",
  format = Documenter.HTML(; canonical = "https://jhidding.github.io/ModuleMixins.jl"),
  pages = [
    "index.md"
    [
      file for
      file in readdir(joinpath(@__DIR__, "src")) if file != "index.md" && splitext(file)[2] == ".md"
    ]
  ],
)

deploydocs(; repo = "github.com/jhidding/ModuleMixins.jl")
