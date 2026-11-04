# ~/~ begin <<docs/src/42-composition-syntax.md#examples/composition/facies.jl>>[init]
using ModuleMixins.Syntactic
using ModuleMixins.Procedural

function describe end

@component module FaciesBase
    import ..describe
    @kwdef struct Facies
        name::String
    end
    @kwdef struct Input
        facies::Vector{Facies} = []
    end
    describe(f::Facies, item) = "facies $(f.name)"
end

@component module Production
    import ..describe
    @mixin FaciesBase
    @kwdef struct Facies
        rate::Float64 = 0.0
    end
    @kwdef struct Input
        scale::Float64 = 1.0
    end
    describe(f::Facies, item) = "produces $(f.rate)"
    total(input) = input.scale * sum(f.rate for f in input.facies)
end

const Model = record_type(:Input, Production)
m = Model(scale = 2.0, facies = [(name = "reef", rate = 3.0), (name = "lagoon", rate = 1.0)])
@show Production.total(m)
for f in m.facies
    println(join((describe(p, f) for p in parts(f)), ", "))
end
# ~/~ end
