# Introduction

`ModuleMixins` is a way of composing families of `struct` definitions on a module level. Suppose we have several modules that contain structs of the same name. We can compose these modules such that all the structs they have in common are merged. Methods that work on one component should now work on the composed type.

!!! info
    Most problems with object type abstraction can be solved in Julia by cleverly using abstract types and multiple dispatch. Use `ModuleMixins` only after you have convinced yourself you absolutely need it.

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
