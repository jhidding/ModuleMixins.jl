# Introduction
The basis for `ModuleMixins` is a single macro: `@compose`. We use that macro to expand a system of interconnected struct definitions in a modular fashion. Each composed module may be refered to as a **component**. In the following example, we have one component `A` with a struct `S` and a second component `B` that expands on `S`.

```@example
using ModuleMixins

@compose module A
  struct S
    a
  end
end

@compose module B
  @mixin A

  struct S
    b
  end
end

fieldnames(B.S)
```

A `struct` within a composed module can be `mutable` and/or `@kwdef`, abstract base types are also forwarded. All `using` and `const` statements are forwarded to the derived module, so that field types still compile.

```@example
using ModuleMixins

@compose module A
  const V = Vector{Int}
  struct S
    a::V
  end
end

@compose module B
  @mixin A
end

typeof(B.S([42]).a)
```

## Diamond pattern

For some use cases you could get away with using more traditional composition techniques
The following pattern of multiple inheritence should work:

```@example 1
using ModuleMixins: @compose

@compose module A
    struct S a::Int end
end

@compose module B
    @mixin A
    struct S b::Int end
end

@compose module C
    @mixin A
    struct S c::Int end
end

@compose module D
    @mixin B, C
    struct S d::Int end
end

fieldnames(D.S)
```

The type `D.S` now has fields `a`, `b`, `c` and `d`.

## Motivation from OOP

Julia is not an object oriented programming (OOP) language. In general, when one speaks of object orientation a mix of a few related concepts is meant:

- Compartimenting program state.
- Message passing between entities.
- Abstraction over interfaces.
- Inheritence or composition.

Where in other languages these concepts are mostly covered by classes, in Julia most of the patterns that are associated with OOP are implemented using multiple dispatch.

The single concept that is not covered by the Julia language or the standard library is inheritance or object composition. Suppose we have two types along with some methods (in the real world these would be much more extensive structs):

```julia
struct A
    x::Int
end

amsg(a::A) = "Hello $(a.x)"

struct B
    y::Int
end

bmsg(b::B) = "Goodbye $(b.y)"
```

Now, for some reason you want to compose those types so that `amsg` and `bmsg` can be called on our new type.

```julia
struct C
    x::Int
    y::Int
end

amsg(c::C) = amsg(A(c.x))
bmsg(c::C) = bmsg(B(c.y))
```

There are some downsides to this: we needed to copy data from `C` into the more primitive types `A` and `B`. We could get around this by removing the types from the original method implementations. Too strict static typing can be a bad thing in Julia!

An alternative approach would be to define `C` differently:

```julia
struct C
    a::A
    b::B
end
```

We would need to abstract over member access using getter and setter methods. When objects grow a bit larger, this type of compositon comes with a lot of boilerplate code. In Julia this is synonymous to: we need macros.

There we have it: if we want any form of composition or inheritance in our types, we need macros to support us.

## Constructors

When you can use inheritance to compose larger objects, it would also be nice if we can construct the larger object without additional code. Suppose we have some `Input` and a `State` struct. It is good to put common definitions in a `Common` module.

```@example 2
using ModuleMixins

module Common
    using Unitful
    export @u_str, Seconds, Kilograms, Meters, Radians, RadiansPerSecond

    const Seconds = typeof(1.0u"s")
    const Kilograms = typeof(1.0u"kg")
    const Meters = typeof(1.0u"m")
    const Radians = typeof(1.0u"rad")
    const RadiansPerSecond = typeof(1.0u"rad/s")
end
```

Our very first component stores the `Input` inside the `State` for later reference:

```@example 2
@compose module ModelBase
    @kwdef struct Input
    end

    struct State{I}
        input::I
    end

    @constructor initial_state(input)::State[input] = (input = input,)
end
```

Notice that we must give the return type of the constructor. All later additions to the constructor must have the same parameter names.

Our first real component introduces time:

```@example 2
@compose module Time
    @mixin ModelBase
    using ..Common

    @kwdef struct Input
        delta_t::Seconds = 0.1u"s"
        steps::Int = 1000
    end

    struct State
        step::Int
    end

    @constructor initial_state(input)::State[step] = (step = 0,)

    time(state) = state.step * state.input.delta_t
end
```

We may model a pendulum:

```@example 2
@compose module Pendulum
    using ..Common
    @mixin Time

    @kwdef struct Input
        length::Meters = 1.0u"m"
        mass::Kilograms = 1.0u"kg"
        initial_angle::Radians = 30.0u"deg"
    end

    struct State
        angle::Radians
        angular_velocity::RadiansPerSecond
    end

    @constructor function initial_state(input)::State[angle, angular_velocity]
        (angle = input.initial_angle,
         angular_velocity = 0.0u"rad/s")
    end
end
```

We can now create an initial state using the default values for input.

```@example 2
Pendulum.initial_state(Pendulum.Input())
```
