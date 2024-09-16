# ~/~ begin <<docs/src/30-blog.md#examples/just_a_spring.jl>>[init]
#| file: examples/just_a_spring.jl
module Spring

using Unitful

# ~/~ begin <<docs/src/30-blog.md#just-a-spring>>[init]
#| id: just-a-spring
@kwdef struct Input
    initial_position::typeof(1.0u"m")
    spring_constant::typeof(1.0u"N/m")
    weight::typeof(1.0u"kg")
    time_step::typeof(1.0u"s")
    time_end::typeof(1.0u"s")
end
# ~/~ end
# ~/~ begin <<docs/src/30-blog.md#just-a-spring>>[1]
#| id: just-a-spring
@kwdef mutable struct State
    time::typeof(1.0u"s")
    position::typeof(1.0u"m")
    velocity::typeof(1.0u"m/s")
end
# ~/~ end
# ~/~ begin <<docs/src/30-blog.md#just-a-spring>>[2]
#| id: just-a-spring
init(input::Input) =
    State(time = 0.0u"s", position = input.initial_position, velocity = 0.0u"m/s")
# ~/~ end
# ~/~ begin <<docs/src/30-blog.md#just-a-spring>>[3]
#| id: just-a-spring
function step!(input::Input, state::State)
    Δt = input.time_step
    Δx = state.velocity * Δt
    Δv = -state.position * input.spring_constant / input.weight * Δt

    state.time += Δt
    state.position += Δx
    state.velocity += Δv
end
# ~/~ end

end

module Script
using Unitful
using CairoMakie
using ..Spring

# ~/~ begin <<docs/src/30-blog.md#spring-run-model>>[init]
#| id: spring-run-model
function run(model::Module, input)
    state = model.init(input)
    Channel{model.State}() do ch
        while state.time < input.time_end
            model.step!(input, state)
            put!(ch, deepcopy(state))
        end
    end
end
# ~/~ end
# ~/~ begin <<docs/src/30-blog.md#spring-plot-result>>[init]
#| id: spring-plot-result
function plot_result(output)
    times = [f.time for f in output]
    pos = [f.position for f in output]

    fig = Figure()
    ax = Axis(fig[1, 1];
        dim1_conversion = Makie.UnitfulConversion(u"s"),
        dim2_conversion = Makie.UnitfulConversion(u"m"),
    )
    lines!(ax, times, pos)
    fig
end
# ~/~ end
# ~/~ begin <<docs/src/30-blog.md#just-a-spring-main>>[init]
#| id: just-a-spring-main
function main()
    input = Spring.Input(
        time_step = 0.01u"s",
        time_end = 5.0u"s",
        spring_constant = 50.0u"N/m",
        initial_position = 1.0u"m",
        weight = 1.0u"kg",
    )

    output = run(Spring, input) |> collect
    fig = plot_result(output)
    save("docs/src/fig/just-a-spring.svg", fig)
end
# ~/~ end
end

Script.main()
# ~/~ end
