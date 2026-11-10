# ~/~ begin <<docs/src/15-tutorial.md#tutorial1>>[init]
module A
    @kwdef struct S
        x::Int
    end
end

module B
    @kwdef struct S
        y::Int
    end
end
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial1>>[1]
using ModuleMixins

module C
    import ..requires, ..A, ..B
    requires(::Val{C}) = (A, B)
end
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial1>>[2]
const Model = record_type(:S, C)

m = Model(x = 6, y = 7)
print("x = $(m.x), y = $(m.y)")
# ~/~ end
