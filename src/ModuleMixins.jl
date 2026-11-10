# ~/~ begin <<docs/src/50-implementation.md#src/ModuleMixins.jl>>[init]
module ModuleMixins

module Common
    """
    Generic function for converting syntax data objects to expressions.
    """
    function to_expression end

    """
        eval_to_expression(mod::Module, obj)

    Generic function for converting syntax data objects to expressions,
    where parts of expressions need to be evaluated in a given module.

    Defaults to calling `to_expression`, dropping the `mod` argument.
    """
    eval_to_expression(mod::Module, obj) = to_expression(obj)

    """
        eval_to_expression(mod::Module)

    Currying version of `eval_to_expression`.
    """
    eval_to_expression(mod::Module) = obj -> eval_to_expression(mod, obj)

    """
    Get name attribute from syntax data object.
    """
    name(obj) = obj.name

    """
        strip_syntax_version(expr)

    From Julia 1.14, a `module` expression may carry the syntax version
    of the code it was parsed from as its first argument:
    `Expr(:module, v"1.14.0", true, name, body)`. Whether it does depends
    on the project the code lives in, not on the Julia version alone.
    Remove the version, so that `@capture` patterns of the form
    `module name_ body__ end` match either way.
    """
    strip_syntax_version(expr) =
        Meta.isexpr(expr, :module) && !isempty(expr.args) && expr.args[1] isa VersionNumber ?
            Expr(:module, expr.args[2:end]...) : expr
end

include("Passes.jl")
include("Spec.jl")
include("Templates.jl")
include("Mixins.jl")
include("Structs.jl")
include("Constructors.jl")
include("Components/Procedural.jl")
include("Components/Syntactic.jl")

using MacroTools: @capture, postwalk
import .Common: name, strip_syntax_version
import .Passes: Pass, pass, no_match, walk
import .Mixins: MixinPass
import .Structs: Struct, CollectStructPass, define_struct
import .Constructors: Constructor, CollectConstructorPass, define_constructor
import .Templates: make_parameter, ModuleTemplate

export @compose, @for_each

using .Procedural
using .Syntactic

export requires, implements, default_implementation, closure,
    record_part, record_type, Composite, parts, component, map_components
export @component

# ~/~ begin <<docs/src/50-implementation.md#compose>>[init]
struct CollectUsingPass <: Pass
    items::Vector{Expr}
end

function pass(p::CollectUsingPass, expr)
    @capture(expr, using x__ | using mod__: x__) || return no_match
    push!(p.items, expr)
    return nothing
end

struct CollectConstPass <: Pass
    items::Vector{Expr}
end

function pass(p::CollectConstPass, expr)
    @capture(expr, const x_ = y_) || return no_match
    push!(p.items, expr)
    return nothing
end

"""
    @compose module Name
        [@mixin Parents, ...]
        ...
    end

Creates a new composable module `Name`. Structs inside this module are
merged with those of the same name in `Parents`.
"""
macro compose(mod)
    @assert @capture(strip_syntax_version(mod), module mod_name_ body__ end)

    # ~/~ begin <<docs/src/50-implementation.md#catch-template-definition>>[init]
    if !isempty(body) && @capture(body[1], {raw_parameters__})
        parameters = raw_parameters .|> make_parameter
        template = ModuleTemplate(mod_name, __module__, parameters, body[2:end])
        return esc(Expr(:toplevel, :(const $mod_name = $template)))
    end
    # ~/~ end

    mixins = Symbol[]
    mixin_tree = IdDict{Symbol, Vector{Symbol}}()
    parents = MixinPass(__module__, [])
    usings = CollectUsingPass([])
    consts = CollectConstPass([])
    struct_items = IdDict{Symbol, Struct}()
    constructor_items = IdDict{Symbol, Constructor}()

    function mixin(expr; mod_name=mod_name)
        structs = CollectStructPass(struct_items, mod_name)
        constructors = CollectConstructorPass(constructor_items)
        parents = MixinPass(__module__, [])
        pass1 = walk(parents, expr)
        mixin_tree[mod_name] = name.(parents.items)
        for p in parents.items
            name(p) in mixins && continue
            push!(mixins, name(p))
            parent_expr = Core.eval(__module__, :($(name(p)).AST))
            mixin(parent_expr; mod_name=name(p))
        end
        walk(usings + consts + structs + constructors, pass1)
    end

    fields = CollectStructPass(IdDict{Symbol,Struct}(), mod_name)
    walk(fields, body)

    clean_body = mixin(body)

    esc(Expr(:toplevel, :(module $mod_name
        const AST = $body
        const PARENTS = [$(QuoteNode.(mixins)...)]
        const MIXIN_TREE = $(mixin_tree)
        const FIELDS = $(IdDict((n => v.fields for (n, v) in pairs(fields.items))...))
        const CONSTRUCTORS = $(constructor_items)
        $(usings.items...)
        $(consts.items...)
        $(define_struct.(values(struct_items))...)
        $(clean_body...)
        $((define_constructor(struct_items[c.return_type_name], c)
            for c in values(constructor_items))...)
    end)))
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#for-each>>[init]
"""
    substitute_top_level(var, val, mod, expr)

Takes a syntax object `expr` and substitutes every occurence of
module `var` for `val`, only if the resulting object is actually
present in module `mod`. The `mod` module should correspond with
a lookup of `val` in the caller's namespace.
"""
function substitute_top_level(var, val, mod, expr)
    postwalk(function (x)
        @capture(x, gen_.item_) || return x
        if gen === var
            if item in names(mod, all=true)
                return Expr(:., val, QuoteNode(item))
            else
                return Returns(nothing)
            end
        end
        return x
    end, expr)
end

"""
    @for_each(M -> M.method(), lst::Vector{Symbol})

Calls `method()` for each module in `lst` that actually implements
that method. Here `lst` should be a vector of symbols that are all
in the current module's namespace.
"""
macro for_each(_fun, _lst)
    @assert @capture(_fun, var_ -> expr_)

    function replace_call_parent(p)
        mod = Core.eval(__module__, p)
        substitute_top_level(var, p, mod, expr)
    end

    lst = Core.eval(__module__, _lst)
    esc(:(begin
        $((replace_call_parent(p) for p in lst)...)
    end))
end
# ~/~ end

end
# ~/~ end
