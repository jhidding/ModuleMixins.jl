# ~/~ begin <<docs/src/16-tutorial-syntax.md#examples/tutorial-syntax5.jl>>[init]
using ModuleMixins.Syntactic
using ModuleMixins.Procedural

initial_state(part, input) = nothing
initial_state(input::Composite) = map_components(p -> initial_state(p, input), input)

@component module A
    import ..initial_state

    @kwdef struct Input
        x0::Int
    end

    @kwdef mutable struct State
        x::Int
    end

    initial_state(::Input, input) = State(x = input.x0)
end

@component module B
    import ..initial_state

    @kwdef struct Input
        y0::Int
    end

    @kwdef mutable struct State
        y::Int
    end

    initial_state(::Input, input) = State(y = input.y0)
end

@component module Model
    @mixin A, B
end

const Input = record_type(:Input, Model)
const State = record_type(:State, Model)

state = initial_state(Input(x0 = 6, y0 = 7))
println(state)
@show state isa State
# ~/~ end
