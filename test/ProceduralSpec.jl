# ~/~ begin <<docs/src/41-composition.md#test/ProceduralSpec.jl>>[init]
module ProceduralSpec
using Test
using ModuleMixins.Procedural
import ModuleMixins.Procedural: requires, implements, default_implementation

abstract type A end
abstract type B end
abstract type C end

module X
    @kwdef struct Input
        x::Int = 1
    end
end

module Y
    @kwdef struct Input
        y::Int = 2
    end
end

module Z
    @kwdef struct Input
        z::Int = 3
    end
end

module W
    using ..X: Input
end

requires(::Val{Y}) = (A, B)
implements(::Val{X}, ::Type{A}) = true
implements(::Val{X}, ::Type{B}) = true
implements(::Val{X}, ::Type{C}) = true
implements(::Val{Z}, ::Type{A}) = true
default_implementation(::Type{A}) = Z

@testset "Procedural" begin
    @test implements(X, A)
    @test implements(X, B)
    @test !implements(Z, B)

    @test closure(Y, X) == (X, Y)
    @test_throws ErrorException closure(Y)  # no default for B
    @test_throws ErrorException closure(Y, X, Z)  # A filled twice

    @test record_part(X, :Input) === X.Input
    @test record_part(X, :State) === nothing
    @test record_part(W, :Input) === nothing  # imported, not defined

    M = record_type(:Input, Y, X)
    m = M(x = 10)
    @test m.x == 10 && m.y == 2
    @test component(m, A) === component(m, B) === component(m, X)
    @test (@inferred component(m, B)) isa X.Input
    @test (@inferred component(m, Val(Y))) isa Y.Input
    @test (@inferred component(m, Y.Input)) isa Y.Input
    @test component(m, Y) isa Y.Input

    # C is not required by any component, so it is found at run time
    @test component(m, C) isa X.Input

    @test_throws ErrorException M(w = 1)
    @test_throws ErrorException component(m, Z)
    @test_throws ErrorException record_type(:State, Y, X)
end

module Owner
    @kwdef struct Item
        name::String = ""
    end
    @kwdef struct Input{Item}
        items::Vector{Item} = []
    end
end

# contributes to `Item`, but not to `Input`
module Extra
    @kwdef struct Item
        weight::Float64 = 1.0
    end
end

module Loop
    struct Input{Input}
        x::Input
    end
end

requires(::Val{Extra}) = (Owner,)

@testset "Procedural records" begin
    M = record_type(:Input, Extra)
    m = M(items = [(name = "a", weight = 2.0), (name = "b",)])
    @test m.items[1].name == "a" && m.items[1].weight == 2.0
    @test m.items[2].weight == 1.0
    @test component(m.items[1], Extra) isa Extra.Item
    @test component(m, Owner) isa Owner.Input
    @test component(m, Owner.Input) isa Owner.Input
    @test_throws ErrorException component(m, Extra)
    @test (@inferred (m -> m.items[1].weight)(m)) == 2.0

    # without `Extra`, items have only the owner's part
    @test record_type(:Input, Owner)(items = [(name = "c",)]).items[1].name == "c"
    @test_throws ErrorException record_type(:Input, Owner)(items = [(weight = 1.0,)])

    @test_throws ErrorException record_type(:Input, Loop)
end
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#test/ProceduralSpec.jl>>[1]
module Grid
    @kwdef struct Cell
        label::String = ""
    end
    @kwdef struct State{Cell, Storage <: AbstractVector{<:AbstractFloat}}
        cells::Vector{Cell} = []
        height::Storage
    end
end

module Growth
    @kwdef struct Cell
        rate::Float64 = 0.0
    end
    @kwdef mutable struct State{Storage}
        growth::Storage
    end
end

requires(::Val{Growth}) = (Grid,)

module Clash
    @kwdef struct State{Storage}
        x::Storage
    end
    struct Storage end
end

using Adapt

Adapt.@adapt_structure Grid.State
Adapt.@adapt_structure Growth.State

struct ToFloat32 end
Adapt.adapt_storage(::ToFloat32, x::Vector{Float64}) = Float32.(x)

@testset "Procedural type parameters" begin
    S = record_type(:State, Growth; Storage = Vector{Float64}, Unused = Int)
    @test isconcretetype(S)
    s = S(cells = [(label = "a", rate = 1.0)], height = [1.0, 2.0], growth = [0.5, 0.5])
    @test s.height isa Vector{Float64}
    @test s.cells[1].rate == 1.0
    @test (@inferred (s -> s.height[2])(s)) == 2.0

    @test_throws ErrorException record_type(:State, Growth)  # Storage not given
    @test_throws TypeError record_type(:State, Growth; Storage = Vector{Int})  # violates bound
    @test_throws ErrorException record_type(:State, Clash; Storage = Int)  # record and keyword

    t = adapt(ToFloat32(), s)
    @test t.height isa Vector{Float32} && t.growth == Float32[0.5, 0.5]
    @test t.cells == s.cells
    @test component(t, Growth) isa Growth.State{Vector{Float32}}
end
end
# ~/~ end
