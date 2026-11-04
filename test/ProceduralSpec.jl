# ~/~ begin <<docs/src/41-composition.md#test/ProceduralSpec.jl>>[init]
module ProceduralSpec
using Test
using ModuleMixins.Procedural
import ModuleMixins.Procedural: requires, implements, default_implementation

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
end
# ~/~ end
