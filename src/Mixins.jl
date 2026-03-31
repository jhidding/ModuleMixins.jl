# ~/~ begin <<docs/src/50-implementation.md#src/Mixins.jl>>[init]
module Mixins

using MacroTools: @capture
import ..Passes: Pass, pass, no_match, walk

@kwdef struct MixinPass <: Pass
    items::Vector{Symbol}
end

function pass(m::MixinPass, expr)
    @capture(expr, @mixin deps_) || return no_match

    if @capture(deps, (multiple_deps__,))
        append!(m.items, multiple_deps)
        :(
            begin
                $([:(using ..$d) for d in multiple_deps]...)
            end
        )
    else
        push!(m.items, deps)
        :(using ..$deps)
    end
end

macro spec_using(mod)
    @assert @capture(mod, module name_ body__ end)

    parents = MixinPass([])
    clean_body = walk(parents, body)

    esc(Expr(:toplevel, :(module $name
        $(clean_body...)
        const AST = $body
        const PARENTS = [$(QuoteNode.(parents.items)...)]
    end)))
end

end
# ~/~ end
