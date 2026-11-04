# ~/~ begin <<docs/src/42-composition-syntax.md#test/SyntacticSpec.jl>>[init]
module SyntacticSpec
using Test
using ModuleMixins.Syntactic
using ModuleMixins.Procedural
import ModuleMixins.Procedural: default_implementation, requires, item_part

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
    @kwdef struct Input <: AbstractSource
        c::Float64 = 1.0
    end
    value(s::Input, model) = s.c
end

default_implementation(::Type{AbstractSource}) = Constant.Input

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
    requires(::Type{Input}) = (AbstractSource,)
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
    @test requires(Sum.Input) == (Double.Input, Square.Input)
    @test requires(Double.Input) == (AbstractSource,)
    @test implements(Ramp.Input, AbstractGradient)
    @test closure(Sum.Input) == (Constant.Input, Double.Input, Square.Input, Sum.Input)

    m = model_type(Sum.Input)(c = 3.0, factor = 10.0)
    @test value(component(m, Sum.Input), m) == 39.0
    r = model_type(Sum.Input, Ramp.Input)(slope = 2.0, x = 1.5)
    @test (@inferred value(component(r, Sum.Input), r)) == 15.0
    @test component(r, AbstractGradient) === component(r, AbstractSource)

    # items are never declared for `Input` itself
    @test item_part(Ramp.Input, Val(:Input)) === nothing
end

@testset "Syntactic errors" begin
    @test_throws ErrorException macroexpand(@__MODULE__, :(@component module NoInput
        struct State end
    end))
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
    @test_throws ErrorException @eval @component module BadRole
        @implements Base.sin
        struct Input end
    end
    @test_throws ErrorException macroexpand(@__MODULE__, :(Syntactic.@mixin Sum))
end

@component module FaciesBase
    @kwdef struct Facies
        name::String
    end

    """
    Input with a documented field type.
    """
    @kwdef struct Input <: Any
        facies::Vector{Facies} = []
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
    mutable struct State
        height::Float64
    end
end

# contributes nothing per item
@component module Time
    @mixin FaciesBase
    @kwdef struct Input
        t_end::Float64 = 1.0
    end
end

@testset "Syntactic items" begin
    @test item_collection(FaciesBase.Input) == (:Facies,)
    @test item_part(Production.Input, Val(:Facies)) === Production.Facies
    @test item_part(Production.Input, Val(:State)) === Production.State
    @test item_part(Time.Input, Val(:Facies)) === nothing

    M = model_type(Production.Input, Time.Input)
    m = M(facies = [(name = "reef", rate = 2.0), (name = "lagoon",)], t_end = 5.0)
    @test m.t_end == 5.0
    @test [f.name for f in m.facies] == ["reef", "lagoon"]
    @test [f.rate for f in m.facies] == [2.0, 0.0]
    @test component(m.facies[1], Production.Facies) isa Production.Facies
    @test component(m, FaciesBase.Input) isa FaciesBase.Input
    @test (@inferred (m -> m.facies[1].rate)(m)) == 2.0

    # only the base part
    b = model_type(FaciesBase.Input)(facies = [(name = "a",)])
    @test b.facies[1].name == "a"
    @test_throws ErrorException model_type(FaciesBase.Input)(facies = [(rate = 1.0,)])
end
end
# ~/~ end
