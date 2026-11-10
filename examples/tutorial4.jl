# ~/~ begin <<docs/src/15-tutorial.md#tutorial4>>[init]
using ModuleMixins

module AgentBase
    @kwdef struct AgentSpec
        name::String
    end

    @kwdef struct Input{AgentSpec}
        agent_specs::Vector{AgentSpec}
    end
end
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial4>>[1]
module Movement
    import ..requires, ..AgentBase

    @kwdef struct AgentSpec
        speed::Float64 = 1.0
    end

    requires(::Val{Movement}) = (AgentBase,)
end

module Lifetime
    import ..requires, ..AgentBase

    @kwdef struct AgentSpec
        max_age::Int
    end

    @kwdef struct Input
        n_steps::Int
    end

    requires(::Val{Lifetime}) = (AgentBase,)
end
# ~/~ end
# ~/~ begin <<docs/src/15-tutorial.md#tutorial4>>[2]
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
