# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax4>>[init]
using ModuleMixins

@component module AgentBase
    @kwdef struct AgentSpec
        name::String
    end

    @kwdef struct Input
        agent_specs::Vector{AgentSpec} = []
    end
end
# ~/~ end
# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax4>>[1]
@show AgentBase.Input isa UnionAll
@show AgentBase.Input.var
# ~/~ end
# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax4>>[2]
@component module Movement
    @mixin AgentBase

    @kwdef struct AgentSpec
        speed::Float64 = 1.0
    end
end

@component module Lifetime
    @mixin AgentBase

    @kwdef struct AgentSpec
        max_age::Int
    end

    @kwdef struct Input
        n_steps::Int
    end
end
# ~/~ end
# ~/~ begin <<docs/src/16-tutorial-syntax.md#tutorial-syntax4>>[3]
const Model = record_type(:Input, Movement, Lifetime)

m = Model(
    n_steps = 10,
    agent_specs = [
        (name = "rabbit", speed = 2.0, max_age = 5),
        (name = "turtle", speed = 0.1, max_age = 100)])

for a in m.agent_specs
    println("$(a.name): speed $(a.speed), lives $(a.max_age) steps")
end
# ~/~ end
