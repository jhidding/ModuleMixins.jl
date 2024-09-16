# ~/~ begin <<docs/src/30-blog.md#examples/mixin_a_spring.jl>>[init]
#| file: examples/mixin_a_spring.jl
using ModuleMixins: @compose

module Common
    # ~/~ begin <<docs/src/30-blog.md#spring-common>>[init]
    #| id: spring-common
    export AbstractInput, AbstractState

    abstract type AbstractInput end
    abstract type AbstractState end
    # ~/~ end
end

@compose module Time
    using Unitful
    using ..Common

    # ~/~ begin <<docs/src/30-blog.md#spring-time>>[init]
    #| id: spring-time
    @kwdef struct Input <: AbstractInput
        time_step::typeof(1.0u"s")
        time_end::typeof(1.0u"s")
    end

    @kwdef mutable struct State <: AbstractState
        time::typeof(1.0u"s")
    end

    function init(input::AbstractInput)
        State(time = 0.0u"s")
    end

    function step!(input::AbstractInput, state::AbstractState; fraction::Float64 = 1.0)
        state.time += fraction * input.time_step
    end
    # ~/~ end
end

@compose module Spring
    @mixin Time
    using Unitful
    using ..Common

    # ~/~ begin <<docs/src/30-blog.md#spring-spring>>[init]
    #| id: spring-spring
    @kwdef struct Input <: AbstractInput
        initial_position::typeof(1.0u"m")
        spring_constant::typeof(1.0u"N/m")
        weight::typeof(1.0u"kg")
    end

    @kwdef mutable struct State <: AbstractState
        position::typeof(1.0u"m")
        velocity::typeof(1.0u"m/s")
    end

    accelleration(input::AbstractInput, state::AbstractState) =
        -state.position * input.spring_constant / input.weight

    step!(input::AbstractInput, state::AbstractState) =
        let a = accelleration(input, state)
            state.position += state.velocity * input.time_step
            state.velocity += a * input.time_step
            Time.step!(input, state)
        end

    init(input::AbstractInput) =
        State(time = 0.0u"s", position = input.initial_position, velocity = 0.0u"m/s")
    # ~/~ end
    # ~/~ begin <<docs/src/30-blog.md#spring-spring>>[1]
    #| id: spring-spring
    kick!(input::AbstractInput, state::AbstractState) =
        state.velocity += accelleration(input, state) * input.time_step

    drift!(input::AbstractInput, state::AbstractState) =
        state.position += state.velocity * input.time_step
    # ~/~ end
end

# ~/~ begin <<docs/src/30-blog.md#mixin-leap-frog>>[init]
#| id: mixin-leap-frog
module LeapFrog
    using ..Common
    using ..Time

    function leap_frog(model::Module)
        function (input::AbstractInput, state::AbstractState)
            model.kick!(input, state)
            Time.step!(input, state; fraction = 0.5)
            model.drift!(input, state)
            Time.step!(input, state; fraction = 0.5)
        end
    end
end
# ~/~ end

module Script
    using Unitful
    using CairoMakie
    using ModuleMixins

    using ..Time
    using ..Spring
    using ..Common
    using ..LeapFrog

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
    # ~/~ begin <<docs/src/30-blog.md#mixin-spring-main>>[init]
    #| id: mixin-spring-main
    @compose module LeapFrogSpring
        @mixin Spring
        using ..LeapFrog: leap_frog

        Base.convert(::Type{State}, s::Spring.State) =
            State(time = s.time, velocity = s.velocity, position = s.position)

        const init = Spring.init
        const step! = leap_frog(Spring)
    end
    # ~/~ end
    # ~/~ begin <<docs/src/30-blog.md#mixin-spring-main>>[1]
    #| id: mixin-spring-main
    function main()
        input = Spring.Input(
            time_step = 0.01u"s",
            time_end = 5.0u"s",
            spring_constant = 50.0u"N/m",
            initial_position = 1.0u"m",
            weight = 1.0u"kg",
        )

        output = run(LeapFrogSpring, input) |> collect
        fig = plot_result(output)
        save("docs/src/fig/mixin-a-spring.svg", fig)
    end
    # ~/~ end
end

Script.main()
# ~/~ end
