# ~/~ begin <<docs/src/30-blog.md#examples/spring-benchmark.jl>>[init]
#| file: examples/spring-benchmark.jl
using BenchmarkTools
using ModuleMixins: @compose

# ~/~ begin <<docs/src/30-blog.md#mixin-a-spring>>[init]
#| id: mixin-a-spring
module Common
    export AbstractInput, AbstractState, Model, run

    abstract type AbstractInput end
    abstract type AbstractState end

    struct Model{T} end

    function run(model::Type{Model{M}}, input) where M
        state = M.init(input)
        Channel{M.State}() do ch
            while state.time < input.time_end
                M.step!(input, state)
                put!(ch, deepcopy(state))
            end
        end
    end
end
# ~/~ end
# ~/~ begin <<docs/src/30-blog.md#mixin-a-spring>>[1]
#| id: mixin-a-spring
@compose module Time
    using Unitful
    using ..Common

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
end
# ~/~ end
# ~/~ begin <<docs/src/30-blog.md#mixin-a-spring>>[2]
#| id: mixin-a-spring
@compose module Spring
    @mixin Time
    using Unitful
    using ..Common

    @kwdef struct Input <: AbstractInput
        initial_position::typeof(1.0u"m")
        spring_constant::typeof(1.0u"N/m")
        mass::typeof(1.0u"kg")
    end

    @kwdef mutable struct State <: AbstractState
        position::typeof(1.0u"m")
        velocity::typeof(1.0u"m/s")
    end

    accelleration(input::AbstractInput, state::AbstractState) =
        -state.position * input.spring_constant / input.mass

    energy(input::AbstractInput, state::AbstractState) =
        let k = state.velocity^2 * input.mass / 2,
            v = state.position^2 * input.spring_constant / 2
            k + v
        end

    step!(input::AbstractInput, state::AbstractState) =
        let a = accelleration(input, state)
            state.position += state.velocity * input.time_step
            state.velocity += a * input.time_step
            Time.step!(input, state)
        end

    init(input::AbstractInput) =
        State(time = 0.0u"s", position = input.initial_position, velocity = 0.0u"m/s")
end
# ~/~ end
# ~/~ begin <<docs/src/30-blog.md#mixin-a-spring>>[3]
#| id: mixin-a-spring
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

    function leap_frog_trait(::Type{Model{T}}) where T
        function (input::AbstractInput, state::AbstractState)
            T.kick!(input, state)
            Time.step!(input, state; fraction = 0.5)
            T.drift!(input, state)
            Time.step!(input, state; fraction = 0.5)
        end
    end

    leap_frog_front(model::Module) = leap_frog_trait(Model{model})
end
# ~/~ end
# ~/~ begin <<docs/src/30-blog.md#mixin-a-spring>>[4]
#| id: mixin-a-spring
@compose module LeapFrogSpring
    @mixin Spring
    using ..Common
    using ..Spring: energy, init, accelleration
    using ..LeapFrog

    Base.convert(::Type{State}, s::Spring.State) =
		State(time=s.time, position=s.position, velocity=s.velocity)

    kick!(input::AbstractInput, state::AbstractState) =
        state.velocity += accelleration(input, state) * input.time_step

    drift!(input::AbstractInput, state::AbstractState) =
        state.position += state.velocity * input.time_step

    const step! = LeapFrog.leap_frog_front(LeapFrogSpring)
    const step_trait! = LeapFrog.leap_frog_trait(Model{LeapFrogSpring})
end
# ~/~ end
# ~/~ begin <<docs/src/30-blog.md#mixin-a-spring>>[5]
#| id: mixin-a-spring
module Script
    using Unitful
    using CairoMakie
    using ModuleMixins

    using ..Time
    using ..Spring
    using ..Common
    using ..LeapFrogSpring

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
        input = LeapFrogSpring.Input(
            time_step = 0.01u"s",
            time_end = 5.0u"s",
            spring_constant = 50.0u"N/m",
            initial_position = 1.0u"m",
            mass = 1.0u"kg",
        )

        output = run(LeapFrogSpring, input) |> collect
        fig = plot_result(LeapFrogSpring, input, output)
        save("docs/src/fig/mixin-a-spring.svg", fig)
    end
end
# ~/~ end

module RawCompute
    using ..Common: AbstractInput, Model
    using ..LeapFrogSpring: Input, State
    using Unitful

    function run(input::Input)
        state = State(time = 0.0u"s", position = input.initial_position, velocity = 0.0u"m/s")
        n_steps = input.time_end / input.time_step |> Int

        for i = 1:n_steps
            a = -state.position * input.spring_constant / input.mass
            state.velocity += a * input.time_step
            state.position += state.velocity * input.time_step
        end
        return state
    end

    function run_abstract(::Type{Model{T}}, input::AbstractInput) where T
        state = T.init(input)
        n_steps = input.time_end / input.time_step |> Int

        for i = 1:n_steps
            T.step!(input, state)
        end
        return state
    end

    function run_trait(::Type{Model{T}}, input::AbstractInput) where T
        state = T.init(input)
        n_steps = input.time_end / input.time_step |> Int

        for i = 1:n_steps
            T.step_trait!(input, state)
        end
        return state
    end

    run_front(model::Module, input::AbstractInput) = run_abstract(Model{model}, input)
end

module Benchmark
    using ..LeapFrogSpring
    using Unitful

    const input = LeapFrogSpring.Input(
        time_step = 0.01u"s",
        time_end = 5.0u"s",
        spring_constant = 50.0u"N/m",
        initial_position = 1.0u"m",
        mass = 1.0u"kg",
    )
end

using .Common
# @benchmark RawCompute.run(Benchmark.input)
# @benchmark RawCompute.run_abstract(LeapFrogSpring, Benchmark.input)
@benchmark RawCompute.run_front(LeapFrogSpring, Benchmark.input)
# ~/~ end
