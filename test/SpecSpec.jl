# ~/~ begin <<docs/src/50-implementation.md#test/SpecSpec.jl>>[init]
# ~/~ begin <<docs/src/50-implementation.md#test-spec-toplevel>>[init]
using ModuleMixins.Spec: @spec, @spec_mixin, @mixin

@spec module MySpec
const msg = "hello"
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#test-spec-toplevel>>[1]
@spec_mixin module MyMixinSpecOne
@mixin A
end
@spec_mixin module MyMixinSpecMany
@mixin A, B, C
end
# ~/~ end

@testset "ModuleMixins.Spec" begin
    using MacroTools: prewalk, rmlines
    clean(expr) = prewalk(rmlines, expr)

    # ~/~ begin <<docs/src/50-implementation.md#test-spec>>[init]
    @testset "@spec" begin
        @test clean.(MySpec.AST) == clean.([:(const msg = "hello")])
        @test MySpec.msg == "hello"
    end
    # ~/~ end
    # ~/~ begin <<docs/src/50-implementation.md#test-spec>>[1]
    @testset "@spec_mixin" begin
        @test MyMixinSpecOne.PARENTS == [:A]
        @test MyMixinSpecMany.PARENTS == [:A, :B, :C]
    end
    # ~/~ end
end
# ~/~ end
