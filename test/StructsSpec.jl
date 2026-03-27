# ~/~ begin <<docs/src/50-implementation.md#test/StructsSpec.jl>>[init]
@testset "ModuleMixins.Structs" begin
    using ModuleMixins.Structs: Struct, parse_struct, define_struct, mangle_type_parameters!
    using MacroTools: prewalk, rmlines
    clean(expr) = prewalk(rmlines, expr)

    # ~/~ begin <<docs/src/50-implementation.md#test-structs>>[init]
    cases = Dict(
        :(struct A x end) => Struct(false, false, :A, nothing, nothing, [:x]),
        :(mutable struct A x end) => Struct(false, true, :A, nothing, nothing, [:x]),
        :(@kwdef struct A x end) => Struct(true, false, :A, nothing, nothing, [:x]),
        :(@kwdef mutable struct A x end) => Struct(true, true, :A, nothing, nothing, [:x]),
        :(struct A{T} x::T end) => Struct(false, false, :A, [:T], nothing, [:(x::T)]),
    )
    
    for (k, v) in pairs(cases)
        @testset "Struct mangling: $(join(split(string(clean(k))), " "))" begin
            @test clean(define_struct(parse_struct(k))) == clean(k)
            @test clean(define_struct(v)) == clean(k)
        end
    end
    # ~/~ end
    # ~/~ begin <<docs/src/50-implementation.md#test-structs>>[1]
    @testset "Struct mangling abstracts" begin
        @test parse_struct(:(struct A <: B x end)).abstract_type == :B
        @test parse_struct(:(mutable struct A <: B x end)).abstract_type == :B
    end
    
    @testset "Mangling type arguments" begin
        let s = parse_struct(:(struct S{T} x::T end))
            @test s.type_parameters == [:T]
            mangle_type_parameters!(s, :A)
            @test s.type_parameters == [:_T_A]
            @test clean(define_struct(s)) == clean(:(struct S{_T_A} x::_T_A end))
        end
        let s = parse_struct(:(struct S{T} x::Vector{T} = [] end))
            mangle_type_parameters!(s, :A)
            @test clean(define_struct(s)) == clean(:(struct S{_T_A} x::Vector{_T_A} = [] end))
        end
    end
    
    @testset "Getting fieldnames" begin
        let s = parse_struct(:(struct S x; y; z end))
            @test fieldnames(s) == [:x, :y, :z]
        end
    end
    # ~/~ end
end
# ~/~ end
