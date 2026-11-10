# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax2>>[init]
using ModuleMixins

@component module Time
    @kwdef struct S
        t::Int
    end
end

@component module A
    @mixin Time

    @kwdef struct S
        x::Int
    end
end

@component module B
    @mixin Time

    @kwdef struct S
        y::Int
    end
end
# ~/~ end
# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax2>>[1]
@show requires(A)
# ~/~ end
# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax2>>[2]
const Model = record_type(:S, A, B)

m = Model(t = 1, x = 6, y = 7)
println("t = $(m.t), x = $(m.x), y = $(m.y)")

@show parts(m)
@show component(m, A)
@show component(m, Time)
# ~/~ end
