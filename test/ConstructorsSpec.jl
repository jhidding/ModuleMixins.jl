# ~/~ begin <<docs/src/50-implementation.md#test/ConstructorsSpec.jl>>[init]
module ConstructorTest
    using ModuleMixins

    @compose module CtA
        struct S
            x
        end

        @constructor make_s()::S[x] = (x = 5,)
    end

    @compose module CtB
        @mixin CtA

        struct S
            y
            z
        end

        @constructor function make_s()::S[y, z]
            (y = 7, z = 9)
        end
    end
end

@testset "ModuleMixins.Constructors" begin
    using .ConstructorTest: CtA, CtB
    using ModuleMixins

    @test CtA.make_s() == CtA.S(5)
    @test CtB.make_s() == CtB.S(5, 7, 9)
end
# ~/~ end
