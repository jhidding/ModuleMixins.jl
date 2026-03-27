# ~/~ begin <<docs/src/50-implementation.md#test/ComposeSpec.jl>>[init]
using ModuleMixins

# ~/~ begin <<docs/src/50-implementation.md#test-compose-toplevel>>[init]
module ComposeTest1
using ModuleMixins

@compose module A
    struct S
        a::Int
    end
end

@compose module B
    struct S{T}
        b::T
    end
end

@compose module AB
    @mixin A, B
end
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#test-compose-toplevel>>[1]
module Common
    export AbstractData
    abstract type AbstractData end
end

@compose module WriterA
    using ..Common

    @kwdef struct Data <: AbstractData
        a::Int
    end

    function write(io::IO, data::AbstractData)
        println(io, data.a)
    end
end

@compose module WriterB
    using ..Common
    @mixin WriterA

    @kwdef struct Data <: AbstractData
        b::Int
    end

    function write(io::IO, data::AbstractData)
        println(io, data.b)
    end
end

@compose module WriterC
end

@compose module WriterABC
    using ModuleMixins
    @mixin WriterB, WriterC

    function write(io::IO, data::AbstractData)
        @for_each(P->P.write(io, data), PARENTS)
    end
end
# ~/~ end

@testset "ModuleMixins.Compose" begin
    using ModuleMixins: @compose

    # ~/~ begin <<docs/src/50-implementation.md#test-compose>>[init]
    @testset "compose struct members" begin
        @test ComposeTest1.AB.PARENTS == [:A, :B]
        @test fieldnames(ComposeTest1.AB.S) == (:a, :b)
    end
    @testset "compose hierarchy" begin
        @test ComposeTest1.AB.MIXIN_TREE == IdDict(:AB => [:A, :B], :A => [], :B => [])
        @test WriterABC.MIXIN_TREE == IdDict(
            :WriterABC => [:WriterB, :WriterC],
            :WriterC => [],
            :WriterB => [:WriterA],
            :WriterA => [])
    end
    @testset "composed struct has type parameter" begin
        @test ComposeTest1.AB.S{Float64}(1, 2).b isa Float64
    end
    # ~/~ end
    # ~/~ begin <<docs/src/50-implementation.md#test-compose>>[1]
    @testset "for-each" begin
        io = IOBuffer(write=true)
        data = WriterABC.Data(a = 42, b = 23)
        WriterABC.write(io, data)
        @test String(take!(io)) == "23\n42\n"
    end
    # ~/~ end
end
# ~/~ end
