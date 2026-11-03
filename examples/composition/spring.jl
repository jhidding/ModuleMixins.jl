# ~/~ begin <<docs/src/41-composition.md#examples/composition/spring.jl>>[init]
include("composition.jl")
using .Composition
import .Composition: requires
using Unitful
using CairoMakie

# ~/~ begin <<docs/src/41-composition.md#spring-common>>[init]
module Common
    using ..Composition: Composite, parts, map_components

    """
        initial_state(part, input)

    The initial state of a single component, or `nothing` if it has no state.
    """
    initial_state(part, input) = nothing
    initial_state(input::Composite) = map_components(p -> initial_state(p, input), input)

    """
        step!(part, input, state)

    Advance the state of a single component. Components step in dependency order.
    """
    step!(part, input, state) = nothing
    step!(input::Composite, state) = foreach(p -> step!(p, input, state), parts(input))

    export initial_state, step!
end
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#spring-time>>[init]
module Time
    using Unitful
    import ..Common: initial_state, step!

    @kwdef struct Input
        t_step::typeof(1.0u"s")
        t_end::typeof(1.0u"s")
    end

    mutable struct State
        time::typeof(1.0u"s")
    end

    initial_state(::Input, input) = State(0.0u"s")
    step!(::Input, input, state) = (state.time += input.t_step)

    function run(input)
        s = initial_state(input)
        Channel() do ch
            while s.time < input.t_end
                step!(input, s)
                put!(ch, deepcopy(s))
            end
        end
    end
end
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#spring-spring>>[init]
module Spring
    using Unitful
    import ..Common: initial_state, step!
    import ..requires
    import ..Time

    @kwdef struct Input
        spring_constant::typeof(1.0u"s^-2")
        initial_position::typeof(1.0u"m")
    end

    mutable struct State
        position::typeof(1.0u"m")
        velocity::typeof(1.0u"m/s")
    end

    requires(::Type{Input}) = (Time.Input,)

    initial_state(::Input, input) = State(input.initial_position, 0.0u"m/s")

    function step!(::Input, input, state)
        delta_v = -input.spring_constant * state.position
        state.position += state.velocity * input.t_step
        state.velocity += delta_v * input.t_step
    end
end
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#spring-damping>>[init]
module Damping
    using Unitful
    import Main.Composition: requires
    import Main.Common: step!
    import Main.Spring

    @kwdef struct Input
        damping::typeof(1.0u"s^-1")
    end

    requires(::Type{Input}) = (Spring.Input,)

    step!(::Input, input, state) =
        (state.velocity -= input.damping * state.velocity * input.t_step)
end
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#spring-run>>[init]
const Model = model_type(Spring.Input)
const DampedModel = model_type(Damping.Input)
@show closure(Damping.Input)

parameters = (
    t_step = 0.001u"s",
    t_end = 1.0u"s",
    spring_constant = 250.0u"s^-2",
    initial_position = 1.0u"m",
)

function plot_result()
    output = Time.run(Model(; parameters...)) |> collect
    damped = Time.run(DampedModel(; parameters..., damping = 3.0u"s^-1")) |> collect

    fig = Figure()
    ax = Axis(fig[1, 1]; xlabel = "time [s]", ylabel = "position [m]")
    for (label, run) in ["spring" => output, "damped spring" => damped]
        lines!(ax, [s.time for s in run] ./ u"s", [s.position for s in run] ./ u"m";
               label = label)
    end
    axislegend(ax)
    save("docs/src/fig/composition-spring.svg", fig)
end

plot_result()
# ~/~ end
# ~/~ end
