# ~/~ begin <<docs/src/42-composition-syntax.md#test/SyntacticSpec.jl>>[init]
module SyntacticSpec
using Test
using ModuleMixins.Syntactic
using ModuleMixins.Procedural
import ModuleMixins.Procedural: default_implementation, requires

abstract type AbstractSource end
abstract type AbstractGradient end
function value end
function gradient end

@component module Ramp
    import ..AbstractSource, ..AbstractGradient, ..value, ..gradient
    @implements AbstractSource, AbstractGradient
    @kwdef struct Input
        slope::Float64 = 1.0
        x::Float64 = 0.0
    end
    value(s::Input, model) = s.slope * s.x
    gradient(s::Input, model) = s.slope
end

@component module Constant
    import ..AbstractSource, ..value
    @implements AbstractSource
    @kwdef struct Input
        c::Float64 = 1.0
    end
    value(s::Input, model) = s.c
end

default_implementation(::Type{AbstractSource}) = Constant

@component module Double
    import ..AbstractSource, ..value
    using ModuleMixins.Procedural: component
    @requires AbstractSource
    @kwdef struct Input
        factor::Float64 = 2.0
    end
    value(d::Input, model) = d.factor * value(component(model, AbstractSource), model)
end

# written by hand
module Square
    import ..AbstractSource, ..value, ..requires
    using ModuleMixins.Procedural: component
    struct Input end
    requires(::Val{Square}) = (AbstractSource,)
    value(::Input, model) = value(component(model, AbstractSource), model)^2
end

@component module Sum
    import ..value
    using ModuleMixins.Procedural: component
    @mixin Double Square
    struct Input end
    value(::Input, model) =
        value(component(model, Double.Input), model) +
        value(component(model, Square.Input), model)
end

@testset "Syntactic" begin
    @test requires(Sum) == (Double, Square)
    @test requires(Double) == (AbstractSource,)
    @test implements(Ramp, AbstractGradient)
    @test !implements(Constant, AbstractGradient)
    @test closure(Sum) == (Constant, Double, Square, Sum)

    m = record_type(:Input, Sum)(c = 3.0, factor = 10.0)
    @test value(component(m, Sum.Input), m) == 39.0
    r = record_type(:Input, Sum, Ramp)(slope = 2.0, x = 1.5)
    @test (@inferred value(component(r, Sum.Input), r)) == 15.0
    @test component(r, AbstractGradient) === component(r, AbstractSource)
end

@testset "Syntactic errors" begin
    @test_throws ErrorException macroexpand(@__MODULE__, :(@component struct Input end))
    @test_throws ErrorException macroexpand(@__MODULE__, :(@component module Parametric
        struct Facies end
        struct Input{T}
            facies::Vector{Facies}
        end
    end))
    @test_throws ErrorException @eval @component module BadMixin
        @mixin AbstractSource
        struct Input end
    end
    @test_throws ErrorException @eval @component module BadRequirement
        @requires Base.sin
        struct Input end
    end
    @test_throws ErrorException @eval @component module BadRole
        @implements Base.sin
        struct Input end
    end
    @test_throws ErrorException macroexpand(@__MODULE__, :(Syntactic.@mixin Sum))
end

@component module FaciesBase
    @kwdef struct Layer
        thickness::Float64 = 1.0
    end

    @kwdef struct Facies
        name::String
        layers::Vector{Layer} = []
    end

    """
    Input with a docstring and a supertype.
    """
    @kwdef struct Input <: Any
        facies::Vector{Facies} = []
    end

    # recursive, not a record containing itself
    struct Tree
        children::Vector{Tree}
    end
end

@component module Production
    @mixin FaciesBase
    @kwdef struct Facies
        rate::Float64 = 0.0
    end
    @kwdef struct Input
        sea_level::Float64 = 0.0
    end
    @kwdef mutable struct State
        height::Float64 = 0.0
    end
end

# contributes nothing per facies
@component module Time
    @mixin FaciesBase
    @kwdef struct Input
        t_end::Float64 = 1.0
    end
end

@testset "Syntactic records" begin
    @test FaciesBase.Input isa UnionAll
    @test FaciesBase.Facies isa UnionAll
    @test FaciesBase.Layer isa DataType
    @test FaciesBase.Tree isa DataType

    M = record_type(:Input, Production, Time)
    m = M(facies = [(name = "reef", rate = 2.0, layers = [(thickness = 3.0,)]), (name = "lagoon",)],
          t_end = 5.0)
    @test m.t_end == 5.0
    @test [f.name for f in m.facies] == ["reef", "lagoon"]
    @test [f.rate for f in m.facies] == [2.0, 0.0]
    @test m.facies[1].layers[1].thickness == 3.0
    @test isempty(m.facies[2].layers)
    @test component(m.facies[1], Production) isa Production.Facies
    @test component(m, FaciesBase) isa FaciesBase.Input
    @test (@inferred (m -> m.facies[1].rate)(m)) == 2.0

    S = record_type(:State, Production, Time)
    @test S(height = 1.0).height == 1.0

    # only the base part
    b = record_type(:Input, FaciesBase)(facies = [(name = "a",)])
    @test b.facies[1].name == "a"
    @test_throws ErrorException record_type(:Input, FaciesBase)(facies = [(rate = 1.0,)])
end
end
# ~/~ end
