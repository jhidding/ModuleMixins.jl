# ~/~ begin <<docs/src/50-implementation.md#test/TemplateMixinSpec.jl>>[init]
module TMSpec
    using ModuleMixins: @compose
    @compose module A{T}
        struct S
            x::T
        end
    end

    @compose module B
        @mixin A{Int}
    end

    @compose module C
        @mixin A{Float64}
    end

    export A, B, C
end

@testset "ModuleMixins.TemplateMixins" begin
    using .TMSpec

    @test fieldtype(B.S, 1) === Int
    @test fieldtype(C.S, 1) === Float64
end
# ~/~ end
