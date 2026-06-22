# Macro passes

Our Big Friendly Macro is implemented in a series of passes. Each pass looks for items in the module that are transformed into different syntax, like structs, mixins and constructors. These passes are made composable so that they run in a single loop.

We use the `prewalk` function (from `MacroTools.jl`) to transform expressions and collect information into searchable data structures. We make a little abstraction over the `prewalk` function, so we can compose multiple transformations in a single tree walk.

An implementation of the `pass` function should take a `Pass` object and an expression (or symbol), and return `no_match` if the expression did not match the pattern.

Types that derive from `Pass` can be added into a composite `CompositePass` using the `+` operator.

```julia
#| file: src/Passes.jl
module Passes

using MacroTools: prewalk

export Pass, pass, no_match, walk

abstract type Pass end

struct NoMatch end

const no_match = NoMatch()

"""
    pass(x::Pass, mod, expr)

Interface. An implementation of the `pass` function should take a `Pass` object
and an expression (or symbol), and return `no_match` if the expression did not
match the pattern.

You can use the given `Pass` object to store information about this pass, return
syntax that should replace the current expression, or `nothing` if it should be
removed.
"""
function pass(x::Pass, mod, expr)
    error("Can't call `pass` on abstract `Pass`.")
end

struct CompositePass <: Pass
    parts::Vector{Pass}
end

Base.:+(a::CompositePass...) = CompositePass(splat(vcat)(getfield.(a, :parts)))
Base.convert(::Type{CompositePass}, a::Pass) = CompositePass([a])
Base.:+(a::Pass...) = splat(+)(convert.(CompositePass, a))

"""
    pass(x::CompositePass, mod, expr)

Tries all passes in a composite pass in order, and returns with the first
that succeeds (i.e. doesn't return `no_match`). You may create a `CompositePass`
by adding passes with the `+` operator.
"""
function pass(cp::CompositePass, mod, expr)
    for p in cp.parts
        result = pass(p, mod, expr)
        if result !== no_match
            return result
        end
    end
    return no_match
end

"""
    walk(x::Pass, mod, expr_list)

Calls `MacroTools.prewalk` with the given `Pass`. If `no_match` is returned,
the expression stays untouched.
"""
function walk(x::Pass, mod, expr_list)
    function patch(expr)
        result = pass(x, mod, expr)
        result === no_match ? expr : result
    end
    prewalk.(patch, expr_list)
end

end
```

A composite pass tries all of its parts in order, returning the value of the first pass that doesn't return `no_match`.

## Tests

!!! details "test/PassesSpec.jl"

    ```julia
    #| file: test/PassesSpec.jl
    @testset "ModuleMixins.Passes" begin
        using ModuleMixins.Passes: Passes, Pass, no_match, pass, walk

        <<test-passes>>
    end
    ```

We define a small pass that replaces some symbol with `blip!`.

```julia
#| id: test-passes
struct BlipPass <: Pass
    tag::Symbol
end

Passes.pass(p::BlipPass, expr) = expr == p.tag ? :blip! : no_match
```

We can test that this works on small tuple expression.

```julia
#| id: test-passes
@testset "pass replacement" begin
    @test walk(BlipPass(:a), [:(a, b)])[1] == :(blip!, b)
    @test walk(BlipPass(:b), [:(a, b)])[1] == :(a, blip!)
end
```

And then that it composes to replace both elements in the tuple.

```julia
#| id: test-passes
@testset "pass composition" begin
    a = BlipPass(:a) + BlipPass(:b)
    @test walk(a, [:(a, b)])[1] == :(blip!, blip!)
end
```
