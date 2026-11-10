# ~/~ begin <<docs/src/15-tutorial.md#tutorial2>>[init]
using ModuleMixins

module Time
    @kwdef struct S
        t::Int
    end
end

module A
    import ..requires, ..Time
    requires(::Val{A}) = (Time,)

    @kwdef struct S
        x::Int
    end
end

module B
    import ..requires, ..Time
    requires(::Val{B}) = (Time,)

    @kwdef struct S
        y::Int
    end
end     
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial2>>[1]
const Model = record_type(:S, A, B)

m = Model(t = 1, x = 6, y = 7)
println("t = $(m.t), x = $(m.x), y = $(m.y)")
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial2>>[2]
@show parts(m)
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial2>>[3]
@show component(m, A)
@show component(m, Time)
# ~/~ end
