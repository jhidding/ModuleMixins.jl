# ~/~ begin <<docs/src/50-implementation.md#test/MixinsSpec.jl>>[init]
using ModuleMixins.Mixins: @spec_using

@testset "ModuleMixins.Mixins" begin
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

    @testset "@spec_using" begin
        @test SU_B.Y == SU_A.X
        @test SU_B.PARENTS == [:SU_A]
        @test SU_D.PARENTS == [:SU_A, :SU_B, :SU_C]
        @test SU_D.SU_C.Z == :goodbye
    end
end
# ~/~ end
