# ~/~ begin <<docs/src/40-studies.md#test/TemplatesSpec.jl>>[init]
using ModuleMixins.Templates: @lambda, @instantiate, ModuleTemplate

@lambda module TempA{T}
    struct S
        x::T
    end
end

@lambda module TempB{M}
    const X = M.X
end

module M1
    const X = 42
end

@testset "ModuleMixins.Templates" begin
    @test TempA isa ModuleTemplate
    @instantiate TempAi = TempA{Int}

    @test TempAi.T === Int
    @test TempAi.S(4).x isa Int

    @instantiate TempAf = TempA{Float64}

    @test TempAf.T === Float64
    @test TempAf.S(4).x isa Float64

    @instantiate TempBM1 = TempB{M1}
    @test TempBM1.X == 42
end
# ~/~ end
