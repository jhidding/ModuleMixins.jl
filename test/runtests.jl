# ~/~ begin <<docs/src/50-implementation.md#test/runtests.jl>>[init]
#| file: test/runtests.jl
using Test
using ModuleMixins:
    @spec,
    @spec_mixin,
    @spec_using,
    @mixin,
    Struct,
    parse_struct,
    define_struct,
    Pass,
    @compose
using MacroTools: prewalk, rmlines

clean(expr) = prewalk(rmlines, expr)

# ~/~ begin <<docs/src/50-implementation.md#test-toplevel>>[init]
#| id: test-toplevel
@spec module MySpec
const msg = "hello"
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#test-toplevel>>[1]
#| id: test-toplevel
@spec_mixin module MyMixinSpecOne
@mixin A
end
@spec_mixin module MyMixinSpecMany
@mixin A, B, C
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#test-toplevel>>[2]
#| id: test-toplevel
@spec_using module SU_A
const X = :hello
export X
end

@spec_using module SU_B
@mixin SU_A
const Y = X
end

@spec_using module SU_C
const Z = :goodbye
end

@spec_using module SU_D
@mixin SU_A
@mixin SU_B, SU_C
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#test-toplevel>>[3]
#| id: test-toplevel
struct EmptyPass <: Pass
    tag::Symbol
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#test-toplevel>>[4]
#| id: test-toplevel
module ComposeTest1
using ModuleMixins: @compose

@compose module A
struct S
    a::Int
end
end

@compose module B
struct S
    b::Int
end
end

@compose module AB
@mixin A, B
end
end
# ~/~ end

@testset "ModuleMixins" begin
    # ~/~ begin <<docs/src/50-implementation.md#test>>[init]
    #| id: test
    @testset "@spec" begin
        @test clean.(MySpec.AST) == clean.([:(const msg = "hello")])
        @test MySpec.msg == "hello"
    end
    # ~/~ end
    # ~/~ begin <<docs/src/50-implementation.md#test>>[1]
    #| id: test
    @testset "@spec_mixin" begin
        @test MyMixinSpecOne.PARENTS == [:A]
        @test MyMixinSpecMany.PARENTS == [:A, :B, :C]
    end
    # ~/~ end
    # ~/~ begin <<docs/src/50-implementation.md#test>>[2]
    #| id: test
    @testset "@spec_using" begin
        @test SU_B.Y == SU_A.X
        @test SU_B.PARENTS == [:SU_A]
        @test SU_D.PARENTS == [:SU_A, :SU_B, :SU_C]
        @test SU_D.SU_C.Z == :goodbye
    end
    # ~/~ end
    # ~/~ begin <<docs/src/50-implementation.md#test>>[3]
    #| id: test
    @testset "pass composition" begin
        a = EmptyPass(:a) + EmptyPass(:b)
        @test a.parts[1].tag == :a
        @test a.parts[2].tag == :b
    end
    # ~/~ end
    # ~/~ begin <<docs/src/50-implementation.md#test>>[4]
    #| id: test
    cases = Dict(
        :(struct A
            x::Any
        end) => Struct(false, false, :A, nothing, [:x]),
        :(mutable struct A
            x::Any
        end) => Struct(false, true, :A, nothing, [:x]),
        :(@kwdef struct A
            x::Any
        end) => Struct(true, false, :A, nothing, [:x]),
        :(@kwdef mutable struct A
            x::Any
        end) => Struct(true, true, :A, nothing, [:x]),
    )

    for (k, v) in pairs(cases)
        @testset "Struct mangling: $(join(split(string(clean(k))), " "))" begin
            @test clean(define_struct(parse_struct(k))) == clean(k)
            @test clean(define_struct(v)) == clean(k)
        end
    end
    # ~/~ end
    # ~/~ begin <<docs/src/50-implementation.md#test>>[5]
    #| id: test
    @testset "Struct mangling abstracts" begin
        @test parse_struct(:(struct A <: B
            x::Any
        end)).abstract_type == :B
        @test parse_struct(:(mutable struct A <: B
            x::Any
        end)).abstract_type == :B
    end
    # ~/~ end
    # ~/~ begin <<docs/src/50-implementation.md#test>>[6]
    #| id: test
    @testset "compose struct members" begin
        @test fieldnames(ComposeTest1.AB.S) == (:a, :b)
    end
    # ~/~ end
end
# ~/~ end
