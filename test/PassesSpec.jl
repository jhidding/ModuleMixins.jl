# ~/~ begin <<docs/src/50-implementation.md#test/PassesSpec.jl>>[init]
@testset "ModuleMixins.Passes" begin
    using ModuleMixins.Passes: Passes, Pass, no_match, pass, walk

    # ~/~ begin <<docs/src/50-implementation.md#test-passes>>[init]
    struct BlipPass <: Pass
        tag::Symbol
    end
    
    Passes.pass(p::BlipPass, expr) = expr == p.tag ? :blip! : no_match
    # ~/~ end
    # ~/~ begin <<docs/src/50-implementation.md#test-passes>>[1]
    @testset "pass replacement" begin
        @test walk(BlipPass(:a), [:(a, b)])[1] == :(blip!, b)
        @test walk(BlipPass(:b), [:(a, b)])[1] == :(a, blip!)
    end
    # ~/~ end
    # ~/~ begin <<docs/src/50-implementation.md#test-passes>>[2]
    @testset "pass composition" begin
        a = BlipPass(:a) + BlipPass(:b)
        @test walk(a, [:(a, b)])[1] == :(blip!, blip!)
    end
    # ~/~ end
end
# ~/~ end
