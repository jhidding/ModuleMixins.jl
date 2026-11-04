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
end
# ~/~ end
