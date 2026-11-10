Tutorial: Procedures
====================

!!! note "New System"
    The new `ModuleMixins` system in version 0.4 has two components: a procedural part completely based on composition and dispatch, and a syntactic part that relieves some of the boilerplate.

Composing Structs
-----------------

We start small. We have two modules `A` and `B`, each with a struct `S`. The struct needs to be defined `@kwdef`.

```julia
#| file: examples/tutorial1.jl
#| id: tutorial1
module A
    @kwdef struct S
        x::Int
    end
end

module B
    @kwdef struct S
        y::Int
    end
end
```

Now we implement a module `C` that merges `A` and `B`. We indicate this relation by dispatching on the `requires` method.

```julia
#| id: tutorial1
using ModuleMixins

module C
    import ..requires, ..A, ..B
    requires(::Val{C}) = (A, B)
end
```

We can now instantiate a composite type using the `record_type` function.

```julia
#| id: tutorial1
const Model = record_type(:S, C)

m = Model(x = 6, y = 7)
print("x = $(m.x), y = $(m.y)")
```

!!! note "Unique field names"
    It is the responsibility of the user to have only unique field names. Having two parts contributing the same name to a record type is an error.

Inheritance
-----------

Now, suppose both `A` and `B` depend on a common component `Time`.

```julia
#| file: examples/tutorial2.jl
#| id: tutorial2
using ModuleMixins

module Time
    @kwdef struct S
        t::Int
    end
end

module A
    import ..requires, ..Time
    requires(::Val{A}) = (Time,)

    @kwdef struct S
        x::Int
    end
end

module B
    import ..requires, ..Time
    requires(::Val{B}) = (Time,)

    @kwdef struct S
        y::Int
    end
end     
```

Now we can create our model again, this time directly from `A` and `B`.

```julia
#| id: tutorial2
const Model = record_type(:S, A, B)

m = Model(t = 1, x = 6, y = 7)
println("t = $(m.t), x = $(m.x), y = $(m.y)")
```

The `Time` component is included once as a transitive requirement.

```julia
#| id: tutorial2
@show parts(m)
```

And we can lift parts of the struct.

```julia
#| id: tutorial2
@show component(m, A)
@show component(m, Time)
```

Abstraction
-----------

Instead of directly depending on a module, it is possible to depend on a `Role`.


```julia
#| file: examples/tutorial3.jl
#| id: tutorial3
using ModuleMixins

abstract type AbstractBuffer end
buffer_push!(m, i) = buffer_push!(component(m, AbstractBuffer), i)
buffer_pop!(m) = buffer_pop!(component(m, AbstractBuffer))
```

The `implements` method is used to indicate if a components implements a certain Role. Here we define two modules that implement the `AbstractBuffer` role. This role has two interfacing methods, for which we forward the call to their specialization.

The `ConstBuffer` ignores everything that comes in and just returns a preset `buffer_value`.

```julia
#| id: tutorial3
module ConstBuffer
    import ..buffer_push!, ..buffer_pop!, ..implements, ..AbstractBuffer

    @kwdef struct S
        buffer_value::Int = 0
    end

    buffer_push!(s::S, item::Int) = nothing
    buffer_pop!(s::S) = s.buffer_value

    implements(::Val{ConstBuffer}, ::Type{AbstractBuffer}) = true
end
```

The `VectorBuffer` pushes and pops from a vector like you would expect.

```julia
#| id: tutorial3
module VectorBuffer
    import ..buffer_push!, ..buffer_pop!, ..implements, ..AbstractBuffer

    @kwdef struct S
        buffer::Vector{Int} = []
    end

    buffer_push!(s::S, item::Int) = push!(s.buffer, item)
    buffer_pop!(s::S) = pop!(s.buffer)

    implements(::Val{VectorBuffer}, ::Type{AbstractBuffer}) = true
end
```

The main module `A` depends on `AbstractBuffer` and uses the defined methods to run a little loop.

```julia
#| id: tutorial3
module A
    import ..requires, ..AbstractBuffer, ..buffer_push!, ..buffer_pop!

    @kwdef struct S
        repeat::Int
    end

    requires(::Val{A}) = (AbstractBuffer,)

    function run(model)
        for i in 1:model.repeat
            buffer_push!(model, i)
            r = buffer_pop!(model)
            println(r)
        end
    end
end
```

Now we can compose two versions of our final "Model".

```julia
#| id: tutorial3
const ConstModel = record_type(:S, A, ConstBuffer)
A.run(ConstModel(repeat=5, buffer_value=9))

const VectorModel = record_type(:S, A, VectorBuffer)
A.run(VectorModel(repeat=5))
```

It is illegal to instantiate a `Composite` type where not all required roles are fulfilled. Running `record_type(:S, A)` will trigger the error: `ERROR: no component implementing role AbstractBuffer was selected, and there is no default`.

### Default Implementation

You may specify a default implementation of a role by dispatching the `default_implementation` method.

```julia
#| id: tutorial3
import ModuleMixins: default_implementation

default_implementation(::Type{AbstractBuffer}) = ConstBuffer
const DefaultModel = record_type(:S, A)
A.run(DefaultModel(repeat=5))
```

!!! note "One part per role"
    When two selected components both implement the same role, an error is raised.

Multiple Types
--------------

In some cases components affect not a single type, but a family of interacting types. For instance, in [CarboKitten](https://mindthegap-erc.github.io/CarboKitten.jl) (the motivating case for `ModuleMixins`) we have a large `Input` struct that contains a list of `Facies` definitions. Similarly, when doing agent-based modelling, you'd have a list of agent specifications in your input.

We need the `AgentSpec` type to be a type variable of the `Input` type. The parameter name `AgentSpec` must be the same as the struct, as it is used to insert the correct composite type when `record_type` is called.

```julia
#| file: examples/tutorial4.jl
#| id: tutorial4
using ModuleMixins

module AgentBase
    @kwdef struct AgentSpec
        name::String
    end

    @kwdef struct Input{AgentSpec}
        agent_specs::Vector{AgentSpec}
    end
end
```

We can now expand on both the `Input` and `AgentSpec` structs.

```julia
#| id: tutorial4
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
```

The rest still works as expected.

```julia
#| id: tutorial4
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

!!! note "Type arguments"

    A type parameter that isn't named after a record is set by a keyword argument to `record_type`, for instance `record_type(:State, Model; Storage = Vector{Float64})`. Components that use the same parameter name share the setting. This is useful for storage that can live on the CPU or a GPU; see [Example: GPU storage](@ref).

Composing Methods
-----------------

Suppose we have a method that is defined on multiple component parts, and we want to call this method on every part automatically. One example we often see returning is to create a constructor for the composite type. In this case we turn an `Input` struct into a mutable `State` struct, using the `initial_state` method.

```julia
#| file: examples/tutorial5.jl
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
```
