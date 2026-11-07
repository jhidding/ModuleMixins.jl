Tutorial
========

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
using ModuleMixins.Procedural

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

Inheritance
-----------

Now, suppose both `A` and `B` depend on a common component `Time`.

```julia
#| file: examples/tutorial2.jl
#| id: tutorial2
using ModuleMixins.Procedural

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
using ModuleMixins.Procedural
import .implements

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
        buffer_value::Int
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

Multiple Types
--------------

In some cases components affect not a single type, but a family of interacting types. For instance, in [CarboKitten](https://mindthegap-erc.github.io/CarboKitten.jl) (the motivating case for `ModuleMixins`) we have a large `Input` struct that contains a list of `Facies` definitions. Similarly, when doing agent-based modelling, you'd have a list of agent specifications in your input.

We need the `AgentSpec` type to be a type variable of the `Input` type.

```julia
#| file: examples/tutorial4.jl
#| id: tutorial4
module AgentBase
    struct AgentSpec end
    struct Input{AgentSpec}
        agent_specs::Vector{AgentSpec}
    end
end
```
