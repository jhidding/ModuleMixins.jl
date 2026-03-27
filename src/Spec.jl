# ~/~ begin <<docs/src/50-implementation.md#src/Spec.jl>>[init]
module Spec

using MacroTools: @capture
export @spec

# ~/~ begin <<docs/src/50-implementation.md#spec>>[init]
"""
    @spec module *name*
        *body*...
    end

Create a spec. The `@spec` macro itself doesn't perform any operations other than creating a module and storing its own AST as `const *name*.AST`.

This macro is only here for teaching purposes.
"""
macro spec(mod)
    @assert @capture(mod, module name_
    body__
    end)

    esc(Expr(:toplevel, :(module $name
    $(body...)
    const AST = $body
    end)))
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#spec>>[1]
macro mixin(deps)
    if @capture(deps, (multiple_deps__,))
        esc(:(const PARENTS = [$(QuoteNode.(multiple_deps)...)]))
    else
        esc(:(const PARENTS = [$(QuoteNode(deps))]))
    end
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#spec>>[2]

macro spec_mixin(mod)
    @assert @capture(mod, module name_
    body__
    end)

    esc(Expr(:toplevel, :(module $name
    import ..@mixin

    $(body...)

    const AST = $body
    end)))
end
# ~/~ end

end
# ~/~ end
