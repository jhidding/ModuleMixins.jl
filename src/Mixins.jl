# ~/~ begin <<docs/src/50-implementation.md#src/Mixins.jl>>[init]
module Mixins

using MacroTools: @capture
import ..Common: to_expression, eval_to_expression, name
import ..Passes: Pass, pass, no_match, walk
using ..Templates: Argument, eval_argument, bind

abstract type AbstractMixin end

struct MixinModule <: AbstractMixin
    name::Symbol
end

to_expression(t::MixinModule) = :(using ..$(t.name))

# ~/~ begin <<docs/src/50-implementation.md#template-expansion>>[init]
struct MixinTemplate <: AbstractMixin
    instance_name::Symbol
    template_name::Symbol
    arguments::Vector{Any}
end

name(t::MixinTemplate) = t.instance_name

function eval_to_expression(mod::Module, t::MixinTemplate)
    template = Core.eval(mod, t.template_name)

    arguments = t.arguments .|> eval_argument(mod)
    bound_vars = bind(template.parameters, arguments)

    module_expr = Expr(:toplevel, :(@compose module $(t.instance_name)
        $(to_expression.(bound_vars)...)
        $(template.body...)
    end))
    @eval(template.environment, $(module_expr))

    return :(using ..$(nameof(template.environment)): $(t.instance_name) as $(t.template_name))
end

function parse_mixin_arg(expr)
    if @capture(expr, name_{raw_arguments__})
        instance_name = gensym(name)
        return MixinTemplate(instance_name, name, raw_arguments)
    elseif expr isa Symbol
        return MixinModule(expr)
    end
    error("illegal mixin target: $(expr)")
end
# ~/~ end

@kwdef struct MixinPass <: Pass
    environment::Module
    items::Vector{AbstractMixin}
end

function pass(m::MixinPass, expr)
    @capture(expr, @mixin raw_deps_) || return no_match

    deps = if @capture(raw_deps, (multiple_deps__,))
        multiple_deps
    else
        [raw_deps]
    end

    targets = deps .|> parse_mixin_arg
    append!(m.items, targets)
    imports = targets .|> eval_to_expression(m.environment)
    return :(begin
        $(imports...)
    end)
end

macro spec_using(mod)
    @assert @capture(mod, module mod_name_ body__ end)

    parents = MixinPass(__module__, [])
    clean_body = walk(parents, body)

    esc(Expr(:toplevel, :(module $mod_name
        $(clean_body...)
        const AST = $body
        const PARENTS = [$(QuoteNode.(name.(parents.items))...)]
    end)))
end

end
# ~/~ end
