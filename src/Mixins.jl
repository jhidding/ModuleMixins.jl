# ~/~ begin <<docs/src/50-implementation.md#src/Mixins.jl>>[init]
module Mixins

using MacroTools: @capture
import ..Passes: Pass, pass, no_match, walk
using ..Templates: Argument, make_argument, bind

struct MixinModule
    name::Symbol
end

struct MixinTemplate
    name::Symbol
    arguments::Vector{Any}
end

function as_expression(mod, target::MixinModule)
    return :(using ..$(target.name))
end

function as_expression(mod, target::MixinTemplate)
    template = getfield(mod, target.name)
    arguments = target.arguments |> make_argument(mod)
    bound_vars = bind(template.parameters, arguments)
    return :(begin
        @compose module $(target.name)
            $(as_expression.(bound_vars)...)
            $(template.body...)
        end

        using .$(target.name)
    end)
end

function parse_mixin_arg(expr)
    if @capture(expr, name_{raw_arguments__})
        return MixinTemplate(name, raw_arguments)
    elseif expr isa Symbol
        return MixinModule(expr)
    end
    error("illegal mixin target: $(expr)")
end

@kwdef struct MixinPass <: Pass
    items::Vector{Union{MixinTemplate,MixinModule}}
end

function pass(m::MixinPass, mod, expr)
    @capture(expr, @mixin deps_) || return no_match

    if @capture(deps, (multiple_deps__,))
        targets = multiple_deps .|> parse_mixin_arg(mod)
        append!(m.items, targets)
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
