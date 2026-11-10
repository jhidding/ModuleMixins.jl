# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax1>>[init]
using ModuleMixins.Syntactic
using ModuleMixins.Procedural

@component module A
    @kwdef struct S
        x::Int
    end
end

@component module B
    @kwdef struct S
        y::Int
    end
end
# ~/~ end
# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax1>>[1]
@component module C
    @mixin A, B
end
# ~/~ end
# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax1>>[2]
const Model = record_type(:S, C)

m = Model(x = 6, y = 7)
print("x = $(m.x), y = $(m.y)")
# ~/~ end
