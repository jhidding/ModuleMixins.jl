# ~/~ begin <<docs/src/20-example.md#examples/spring.jl>>[init]
#| file: examples/spring.jl

using ModuleMixins
using CairoMakie
using Unitful

module Common
    abstract type AbstractInput end
    abstract type AbstractState end

    function initial_state(input::AbstractInput)
        error("Can't construct from AbstractInput")
    end

    export AbstractInput, AbstractState, initial_state
end

# ~/~ begin <<docs/src/20-example.md#example-time>>[init]
#| id: example-time

@compose module Time
    using Unitful
    using ..Common

    @kwdef struct Input <: AbstractInput
        t_step::typeof(1.0u"s")
        t_end::typeof(1.0u"s")
    end

    mutable struct State <: AbstractState
        time::typeof(1.0u"s")
    end

    function step!(input::AbstractInput, state::AbstractState)
        state.time += input.t_step
    end

    function run(model, input::AbstractInput)
        s = model.initial_state(input)
        Channel() do ch
            while s.time < input.t_end
                model.step!(input, s)
                put!(ch, deepcopy(s))
            end
        end
    end
end
# ~/~ end
# ~/~ begin <<docs/src/20-example.md#example-spring>>[init]
#| id: example-spring

@compose module Spring
    @mixin Time
    using ..Common
    using Unitful

    @kwdef struct Input <: AbstractInput
        spring_constant::typeof(1.0u"s^-2")
        initial_position::typeof(1.0u"m")
    end

    mutable struct State <: AbstractState
        position::typeof(1.0u"m")
        velocity::typeof(1.0u"m/s")
    end

    function step!(input::AbstractInput, state::AbstractState)
        delta_v = -input.spring_constant * state.position
        state.position += state.velocity * input.t_step
        state.velocity += delta_v * input.t_step
    end
end
# ~/~ end
# ~/~ begin <<docs/src/20-example.md#example-run>>[init]
#| id: example-run

@compose module Model
    @mixin Time, Spring
    using ..Common
    using Unitful

    function step!(input::Input, state::State)
        Spring.step!(input, state)
        Time.step!(input, state)
    end

    function initial_state(input::Input)
        return State(0.0u"s", input.initial_position, 0.0u"m/s")
    end
end
# ~/~ end
# ~/~ begin <<docs/src/20-example.md#example-run>>[1]
#| id: example-run

function plot_result()
    input = Model.Input(
        t_step = 0.001u"s",
        t_end = 1.0u"s",
        spring_constant = 250.0u"s^-2",
        initial_position = 1.0u"m")

    output = Time.run(model, input) |> collect
    times = [f.time for f in output]
    pos = [f.position for f in output]

    fig = Figure()
    ax = Axis(fig[1, 1])
    lines!(ax, times, pos)
    save("docs/src/fig/plot.svg", fig)
end

plot_result()
# ~/~ end
# ~/~ end