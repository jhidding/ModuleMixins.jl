# ~/~ begin <<docs/src/50-implementation.md#src/Passes.jl>>[init]
module Passes

using MacroTools: prewalk

export Pass, pass, no_match, walk

abstract type Pass end

struct NoMatch end

const no_match = NoMatch()

"""
    pass(x::Pass, expr)

Interface. An implementation of the `pass` function should take a `Pass` object
and an expression (or symbol), and return `no_match` if the expression did not
match the pattern.

You can use the given `Pass` object to store information about this pass, return
syntax that should replace the current expression, or `nothing` if it should be
removed.
"""
function pass(x::Pass, expr)
    error("Can't call `pass` on abstract `Pass`.")
end

struct CompositePass <: Pass
    parts::Vector{Pass}
end

Base.:+(a::CompositePass...) = CompositePass(splat(vcat)(getfield.(a, :parts)))
Base.convert(::Type{CompositePass}, a::Pass) = CompositePass([a])
Base.:+(a::Pass...) = splat(+)(convert.(CompositePass, a))

"""
    pass(x::CompositePass, expr)

Tries all passes in a composite pass in order, and returns with the first
that succeeds (i.e. doesn't return `no_match`). You may create a `CompositePass`
by adding passes with the `+` operator.
"""
function pass(cp::CompositePass, expr)
    for p in cp.parts
        result = pass(p, expr)
        if result !== no_match
            return result
        end
    end
    return no_match
end

"""
    walk(x::Pass, expr_list)

Calls `MacroTools.prewalk` with the given `Pass`. If `no_match` is returned,
the expression stays untouched.
"""
function walk(x::Pass, expr_list)
    function patch(expr)
        result = pass(x, expr)
        result === no_match ? expr : result
    end
    prewalk.(patch, expr_list)
end

end
# ~/~ end
