# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax3>>[init]
using ModuleMixins

abstract type AbstractBuffer end
function buffer_push! end
function buffer_pop! end
buffer_push!(m, i) = buffer_push!(component(m, AbstractBuffer), i)
buffer_pop!(m) = buffer_pop!(component(m, AbstractBuffer))
# ~/~ end
# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax3>>[1]
@component module ConstBuffer
    import ..buffer_push!, ..buffer_pop!, ..AbstractBuffer
    @implements AbstractBuffer

    @kwdef struct S
        buffer_value::Int = 0
    end

    buffer_push!(s::S, item::Int) = nothing
    buffer_pop!(s::S) = s.buffer_value
end

@component module VectorBuffer
    import ..buffer_push!, ..buffer_pop!, ..AbstractBuffer
    @implements AbstractBuffer

    @kwdef struct S
        buffer::Vector{Int} = []
    end

    buffer_push!(s::S, item::Int) = push!(s.buffer, item)
    buffer_pop!(s::S) = pop!(s.buffer)
end
# ~/~ end
# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax3>>[2]
@component module A
    import ..AbstractBuffer, ..buffer_push!, ..buffer_pop!
    @requires AbstractBuffer

    @kwdef struct S
        repeat::Int
    end

    function run(model)
        for i in 1:model.repeat
            buffer_push!(model, i)
            r = buffer_pop!(model)
            println(r)
        end
    end
end
# ~/~ end
# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax3>>[3]
const ConstModel = record_type(:S, A, ConstBuffer)
A.run(ConstModel(repeat=5, buffer_value=9))

const VectorModel = record_type(:S, A, VectorBuffer)
A.run(VectorModel(repeat=5))
# ~/~ end
# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax3>>[4]
import ModuleMixins: default_implementation

default_implementation(::Type{AbstractBuffer}) = ConstBuffer
const DefaultModel = record_type(:S, A)
A.run(DefaultModel(repeat=5))
# ~/~ end
