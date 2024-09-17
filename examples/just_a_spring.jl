# ~/~ begin <<docs/src/30-blog.md#examples/just_a_spring.jl>>[init]
#| file: examples/just_a_spring.jl
#| classes: ["task"]
#| creates:
#|   - docs/src/fig/just-a-spring.svg
#| collect: figures
module Spring
    # ~/~ begin <<docs/src/30-blog.md#just-a-spring>>[init]
    #| id: just-a-spring
    using Unitful

    @kwdef struct Input
        initial_position::typeof(1.0u"m")
        spring_constant::typeof(1.0u"N/m")
        mass::typeof(1.0u"kg")
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
        Δv = -state.position * input.spring_constant / input.mass * Δt

        state.time += Δt
        state.position += Δx
        state.velocity += Δv
    end
    # ~/~ end
    # ~/~ begin <<docs/src/30-blog.md#just-a-spring>>[4]
    #| id: just-a-spring
    function energy(input::Input, state::State)
        k = state.velocity^2 * input.mass / 2
        v = state.position^2 * input.spring_constant / 2
        return k + v
    end
    # ~/~ end
end

# ~/~ begin <<docs/src/30-blog.md#spring-model>>[init]
#| id: spring-model
module Model
    function run(model::Module, input)
        state = model.init(input)
        Channel{model.State}() do ch
            while state.time < input.time_end
                model.step!(input, state)
                put!(ch, deepcopy(state))
            end
        end
    end
end
# ~/~ end

module Script
    using Unitful
    using CairoMakie
    using ..Spring
    using ..Model: run

    # ~/~ begin <<docs/src/30-blog.md#spring-plot>>[init]
    #| id: spring-plot
    function plot_result(model, input, output)
        times = [f.time for f in output]
        pos = [f.position for f in output]

        fig = Figure()
        ax1 = Axis(fig[1:2, 1];
            ylabel = "position",
            dim1_conversion = Makie.UnitfulConversion(u"s"),
            dim2_conversion = Makie.UnitfulConversion(u"m"),
        )
        lines!(ax1, times, pos)
        ax2 = Axis(fig[3, 1];
            ylabel = "energy",
            dim1_conversion = Makie.UnitfulConversion(u"s"),
            dim2_conversion = Makie.UnitfulConversion(u"J"),
        )
        lines!(ax2, times, [model.energy(input, s) for s in output])
        fig
    end
    # ~/~ end

    function main()
        input = Spring.Input(
            time_step = 0.01u"s",
            time_end = 5.0u"s",
            spring_constant = 50.0u"N/m",
            initial_position = 1.0u"m",
            mass = 1.0u"kg",
        )

        output = run(Spring, input) |> collect
        fig = plot_result(Spring, input, output)
        save("docs/src/fig/just-a-spring.svg", fig)
    end
end

Script.main()
# ~/~ end
