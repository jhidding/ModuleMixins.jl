# ~/~ begin <<docs/src/41-composition.md#test/ProceduralSpec.jl>>[init]
module ProceduralSpec
using Test
using ModuleMixins.Procedural
import ModuleMixins.Procedural: requires, implements, default_implementation,
    item_collection, item_part

abstract type A end
abstract type B end
abstract type C end

@kwdef struct X <: A
    x::Int = 1
end
@kwdef struct Y
    y::Int = 2
end
@kwdef struct Z <: A
    z::Int = 3
end

requires(::Type{Y}) = (A, B)
implements(::Type{X}, ::Type{B}) = true
implements(::Type{X}, ::Type{C}) = true
default_implementation(::Type{A}) = Z

@testset "Procedural" begin
    @test implements(X, A)
    @test implements(X, B)
    @test !implements(Z, B)

    @test closure(Y, X) == (X, Y)
    @test_throws ErrorException closure(Y)  # no default for B
    @test_throws ErrorException closure(Y, X, Z)  # A filled twice

    M = model_type(Y, X)
    m = M(x = 10)
    @test m.x == 10 && m.y == 2
    @test component(m, A) === component(m, B) === component(m, X)
    @test (@inferred component(m, B)) isa X

    # C is not required by any component, so it is found at run time
    @test component(m, C) isa X

    @test_throws ErrorException M(w = 1)
    @test_throws ErrorException component(m, Z)
end

# per-item records: `Owner` holds items, `Owner` and `Extra` contribute parts
@kwdef struct OwnerItem
    name::String = ""
end
@kwdef struct Owner{I}
    items::Vector{I} = []
end
@kwdef struct ExtraItem
    weight::Float64 = 1.0
end
struct Extra end

requires(::Type{Extra}) = (Owner,)
item_collection(::Type{<:Owner}) = (:Item,)
item_part(::Type{<:Owner}, ::Val{:Item}) = OwnerItem
item_part(::Type{Extra}, ::Val{:Item}) = ExtraItem

@testset "Procedural items" begin
    M = model_type(Extra)
    m = M(items = [(name = "a", weight = 2.0), (name = "b",)])
    @test m.items[1].name == "a" && m.items[1].weight == 2.0
    @test m.items[2].weight == 1.0
    @test component(m.items[1], ExtraItem) isa ExtraItem
    @test component(m, Owner) isa Owner
    @test (@inferred (m -> m.items[1].weight)(m)) == 2.0

    # without `Extra`, items have only the owner's part
    @test model_type(Owner)(items = [(name = "c",)]).items[1].name == "c"
    @test_throws ErrorException model_type(Owner)(items = [(weight = 1.0,)])
end
end
# ~/~ end
