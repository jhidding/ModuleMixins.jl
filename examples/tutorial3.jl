# ~/~ begin <<docs/src/15-tutorial.md#tutorial3>>[init]
using ModuleMixins.Procedural

abstract type AbstractBuffer end
buffer_push!(m, i) = buffer_push!(component(m, AbstractBuffer), i)
buffer_pop!(m) = buffer_pop!(component(m, AbstractBuffer))
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial3>>[1]
module ConstBuffer
    import ..buffer_push!, ..buffer_pop!, ..implements, ..AbstractBuffer

    @kwdef struct S
        buffer_value::Int = 0
    end

    buffer_push!(s::S, item::Int) = nothing
    buffer_pop!(s::S) = s.buffer_value

    implements(::Val{ConstBuffer}, ::Type{AbstractBuffer}) = true
end
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial3>>[2]
module VectorBuffer
    import ..buffer_push!, ..buffer_pop!, ..implements, ..AbstractBuffer

    @kwdef struct S
        buffer::Vector{Int} = []
    end

    buffer_push!(s::S, item::Int) = push!(s.buffer, item)
    buffer_pop!(s::S) = pop!(s.buffer)

    implements(::Val{VectorBuffer}, ::Type{AbstractBuffer}) = true
end
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial3>>[3]
module A
    import ..requires, ..AbstractBuffer, ..buffer_push!, ..buffer_pop!

    @kwdef struct S
        repeat::Int
    end

    requires(::Val{A}) = (AbstractBuffer,)

    function run(model)
        for i in 1:model.repeat
            buffer_push!(model, i)
            r = buffer_pop!(model)
            println(r)
        end
    end
end
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial3>>[4]
const ConstModel = record_type(:S, A, ConstBuffer)
A.run(ConstModel(repeat=5, buffer_value=9))

const VectorModel = record_type(:S, A, VectorBuffer)
A.run(VectorModel(repeat=5))
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial3>>[5]
import ModuleMixins.Procedural: default_implementation

default_implementation(::Type{AbstractBuffer}) = ConstBuffer
const DefaultModel = record_type(:S, A)
A.run(DefaultModel(repeat=5))
# ~/~ end
