Tutorial: Syntax
================

This tutorial repeats the [previous one](@ref "Tutorial") step by step, using the `@component` macro from `ModuleMixins.Syntactic`. The macro is shorthand only: every `@component` module expands to a plain module plus a few methods of `requires` and `implements`, exactly the ones we wrote by hand before. You can mix both styles.

Composing Structs
-----------------

Modules `A` and `B` each define a struct `S`. Since they have no dependencies, `@component` doesn't add anything yet.

```julia
#| file: examples/tutorial-syntax1.jl
#| id: tutorial-syntax1
using ModuleMixins.Syntactic
using ModuleMixins.Procedural

@component module A
    @kwdef struct S
        x::Int
    end
end

@component module B
    @kwdef struct S
        y::Int
    end
end
```

Module `C` merges `A` and `B`. Instead of importing `requires` and extending it, we write `@mixin A, B`. This imports `A` and `B` from the parent module and declares them as requirements.

```julia
#| id: tutorial-syntax1
@component module C
    @mixin A, B
end
```

The record type is created just like before.

```julia
#| id: tutorial-syntax1
const Model = record_type(:S, C)

m = Model(x = 6, y = 7)
print("x = $(m.x), y = $(m.y)")
```

Inheritance
-----------

Both `A` and `B` depend on a common component `Time`.

```julia
#| file: examples/tutorial-syntax2.jl
#| id: tutorial-syntax2
using ModuleMixins.Syntactic
using ModuleMixins.Procedural

@component module Time
    @kwdef struct S
        t::Int
    end
end

@component module A
    @mixin Time

    @kwdef struct S
        x::Int
    end
end

@component module B
    @mixin Time

    @kwdef struct S
        y::Int
    end
end
```

The `@mixin` declaration expands to the same `requires(::Val{A}) = (Time,)` that we wrote by hand.

```julia
#| id: tutorial-syntax2
@show requires(A)
```

The rest is unchanged.

```julia
#| id: tutorial-syntax2
const Model = record_type(:S, A, B)

m = Model(t = 1, x = 6, y = 7)
println("t = $(m.t), x = $(m.x), y = $(m.y)")

@show parts(m)
@show component(m, A)
@show component(m, Time)
```

Abstraction
-----------

The role `AbstractBuffer` and its interface are defined as before. Defining a role doesn't involve any macros.

```julia
#| file: examples/tutorial-syntax3.jl
#| id: tutorial-syntax3
using ModuleMixins.Syntactic
using ModuleMixins.Procedural

abstract type AbstractBuffer end
function buffer_push! end
function buffer_pop! end
buffer_push!(m, i) = buffer_push!(component(m, AbstractBuffer), i)
buffer_pop!(m) = buffer_pop!(component(m, AbstractBuffer))
```

A component declares that it fills a role with `@implements`. We still need to import the role and the interface methods we extend: `@component` only takes care of `requires` and `implements`.

```julia
#| id: tutorial-syntax3
@component module ConstBuffer
    import ..buffer_push!, ..buffer_pop!, ..AbstractBuffer
    @implements AbstractBuffer

    @kwdef struct S
        buffer_value::Int = 0
    end

    buffer_push!(s::S, item::Int) = nothing
    buffer_pop!(s::S) = s.buffer_value
end

@component module VectorBuffer
    import ..buffer_push!, ..buffer_pop!, ..AbstractBuffer
    @implements AbstractBuffer

    @kwdef struct S
        buffer::Vector{Int} = []
    end

    buffer_push!(s::S, item::Int) = push!(s.buffer, item)
    buffer_pop!(s::S) = pop!(s.buffer)
end
```

A dependency on a role is declared with `@requires`. Where `@mixin` names a component and imports it, `@requires` takes any requirement, component or role, and imports nothing.

```julia
#| id: tutorial-syntax3
@component module A
    import ..AbstractBuffer, ..buffer_push!, ..buffer_pop!
    @requires AbstractBuffer

    @kwdef struct S
        repeat::Int
    end

    function run(model)
        for i in 1:model.repeat
            buffer_push!(model, i)
            r = buffer_pop!(model)
            println(r)
        end
    end
end
```

Composing the models is the same as before.

```julia
#| id: tutorial-syntax3
const ConstModel = record_type(:S, A, ConstBuffer)
A.run(ConstModel(repeat=5, buffer_value=9))

const VectorModel = record_type(:S, A, VectorBuffer)
A.run(VectorModel(repeat=5))
```

### Default Implementation

A default implementation of a role doesn't belong to any single component, so there's no syntax for it: we extend `default_implementation` just like in the procedural version.

```julia
#| id: tutorial-syntax3
import ModuleMixins.Procedural: default_implementation

default_implementation(::Type{AbstractBuffer}) = ConstBuffer
const DefaultModel = record_type(:S, A)
A.run(DefaultModel(repeat=5))
```

The macro also catches some mistakes early. For instance, `@implements` with something that isn't a type, or `@mixin` with something that isn't a module, raises an error as soon as the component is defined, instead of when the model is composed.

Multiple Types
--------------

Now for the family of interacting types: an `Input` containing a list of agent specifications. Each component may contribute fields to the `Input`, to the `AgentSpec`, or to both.

```julia
#| file: examples/tutorial-syntax4.jl
#| id: tutorial-syntax4
using ModuleMixins.Syntactic
using ModuleMixins.Procedural

@component module AgentBase
    @kwdef struct AgentSpec
        name::String
    end

    @kwdef struct Input
        agent_specs::Vector{AgentSpec} = []
    end
end
```

In the procedural version we had to make `AgentSpec` a type parameter of `Input` ourselves. The `@component` macro sees that a field of `Input` mentions `AgentSpec`, another struct in the same module, and adds the type parameter for us, so `Input` is really `Input{AgentSpec}`.

```julia
#| id: tutorial-syntax4
@show AgentBase.Input isa UnionAll
@show AgentBase.Input.var
```

Other components add their own fields to `AgentSpec` and `Input` by defining structs of the same name. A component doesn't need to contribute to every record: `Movement` only adds a field to `AgentSpec`.

```julia
#| id: tutorial-syntax4
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
```

When we create the `Input` record, `AgentSpec` is filled in with the composite of all `AgentSpec` parts. The agent specifications can be given as named tuples, which are converted to the composite type.

```julia
#| id: tutorial-syntax4
const Model = record_type(:Input, Movement, Lifetime)

m = Model(
    n_steps = 10,
    agent_specs = [
        (name = "rabbit", speed = 2.0, max_age = 5),
        (name = "turtle", speed = 0.1, max_age = 100)])

for a in m.agent_specs
    println("$(a.name): speed $(a.speed), lives $(a.max_age) steps")
end
```

Composing Methods
-----------------

To call a method on every part of a composite, we use `map_components`. Here `initial_state` turns an `Input` into a mutable `State`. Every component turns its own `Input` part into its own `State` part, and the results are composed into a new `Composite`. The method definitions are plain Julia, so they look the same as in the procedural version.

```julia
#| file: examples/tutorial-syntax5.jl
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
```
