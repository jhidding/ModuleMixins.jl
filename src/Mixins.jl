# ~/~ begin <<docs/src/50-implementation.md#src/Mixins.jl>>[init]
module Mixins

using MacroTools: @capture
import ..Passes: Pass, pass, no_match, walk
using ..Templates: Argument, eval_argument, bind

struct MixinModule
    name::Symbol
end

to_symbol(m::MixinModule) = m.name

struct MixinTemplate
    name::Symbol
    arguments::Vector{Any}
end

function as_expression(target::MixinModule)
    return :(using ..$(target.name))
end

function to_module(mod)
    _to_module(t::MixinModule) = t

    function _to_module(t::MixinTemplate)
        template = @eval(mod, t.name)

        arguments = t.arguments .|> eval_argument(mod)
        bound_vars = bind(template.parameters, arguments)
        instance_name = gensym(t.name)

        module_expr = Expr(:toplevel, :(@compose module $(instance_name)
            $(as_expression.(bound_vars)...)
            $(template.body...)
        end))
        @eval(template.environment, $(module_expr))

        return MixinModule(instance_name)
    end

    return _to_module
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
    environment::Module
    items::Vector{Symbol}
end

function pass(m::MixinPass, expr)
    @capture(expr, @mixin raw_deps_) || return no_match

    deps = if @capture(raw_deps, (multiple_deps__,))
        multiple_deps
    else
        [raw_deps]
    end

    targets = deps .|> parse_mixin_arg .|> to_module(m.environment)
    append!(m.items, targets .|> to_symbol)
    return :(begin
        $((targets .|> as_expression)...)
    end)
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
