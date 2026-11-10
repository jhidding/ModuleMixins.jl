# ~/~ begin <<docs/src/15-tutorial.md#examples/tutorial5.jl>>[init]
import ModuleMixins: map_components, record_type, Composite

initial_state(part, input) = nothing
initial_state(input::Composite) = map_components(p -> initial_state(p, input), input)

module A
    import ..initial_state

    @kwdef struct Input
        x0::Int
    end

    @kwdef mutable struct State
        x::Int
    end

    initial_state(::Input, input) = State(x = input.x0)
end

module B
    import ..initial_state

    @kwdef struct Input
        y0::Int
    end

    @kwdef mutable struct State
        y::Int
    end

    initial_state(::Input, input) = State(y = input.y0)
end

module Model
    import ..record_type, ..A, ..B
    const Input = record_type(:Input, A, B)
    const State = record_type(:State, A, B)
end

println(initial_state(Model.Input(x0=6, y0=7)))
# ~/~ end
