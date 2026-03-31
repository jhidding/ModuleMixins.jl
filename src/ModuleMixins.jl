# ~/~ begin <<docs/src/50-implementation.md#src/ModuleMixins.jl>>[init]
module ModuleMixins

include("Passes.jl")
include("Spec.jl")
include("Mixins.jl")
include("Structs.jl")
include("Constructors.jl")

using MacroTools: @capture, postwalk
import .Passes: Pass, pass, no_match, walk
import .Mixins: MixinPass
import .Structs: Struct, CollectStructPass, define_struct
import .Constructors: Constructor, CollectConstructorPass, define_constructor

export @compose, @for_each

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
    @assert @capture(mod, module name_ body__ end)

    mixins = Symbol[]
    mixin_tree = IdDict{Symbol, Vector{Symbol}}()
    parents = MixinPass([])
    usings = CollectUsingPass([])
    consts = CollectConstPass([])
    struct_items = IdDict{Symbol, Struct}()
    constructor_items = IdDict{Symbol, Constructor}()

    function mixin(expr; name=name)
        structs = CollectStructPass(struct_items, name)
        constructors = CollectConstructorPass(constructor_items)
        parents = MixinPass([])
        pass1 = walk(parents, expr)
        mixin_tree[name] = parents.items
        for p in parents.items
            p in mixins && continue
            push!(mixins, p)
            parent_expr = Core.eval(__module__, :($(p).AST))
            mixin(parent_expr; name=p)
        end
        walk(usings + consts + structs + constructors, pass1)
    end

    fields = CollectStructPass(IdDict{Symbol,Struct}(), name)
    walk(fields, body)

    clean_body = mixin(body)

    esc(Expr(:toplevel, :(module $name
        const AST = $body
        const PARENTS = [$(QuoteNode.(mixins)...)]
        const MIXIN_TREE = $(mixin_tree)
        const FIELDS = $(IdDict((n => v.fields for (n, v) in pairs(fields.items))...))
        const CONSTRUCTORS = $(constructor_items)
        $(usings.items...)
        $(consts.items...)
        $(define_struct.(values(struct_items))...)
        $((define_constructor(struct_items[c.return_type_name], c)
            for c in values(constructor_items))...)
        $(clean_body...)
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
