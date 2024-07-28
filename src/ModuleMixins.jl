# ~/~ begin <<docs/src/50-implementation.md#src/ModuleMixins.jl>>[init]
#| file: src/ModuleMixins.jl
module ModuleMixins

using MacroTools: @capture, postwalk, prewalk

export @compose

# ~/~ begin <<docs/src/50-implementation.md#spec>>[init]
#| id: spec
"""
    @spec module *name*
        *body*...
    end

Create a spec. The `@spec` macro itself doesn't perform any operations other than creating a module and storing its own AST as `const *name*.AST`.
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
#| id: spec

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
# ~/~ begin <<docs/src/50-implementation.md#spec>>[2]
#| id: spec

abstract type Pass end

function pass(x::Pass, expr)
    error("Can't call `pass` on abstract `Pass`.")
end

struct CompositePass <: Pass
    parts::Vector{Pass}
end

Base.:+(a::CompositePass...) = CompositePass(splat(vcat)(getfield.(a, :parts)))
Base.convert(::Type{CompositePass}, a::Pass) = CompositePass([a])
Base.:+(a::Pass...) = splat(+)(convert.(CompositePass, a))

function pass(cp::CompositePass, expr)
    for p in cp.parts
        result = pass(p, expr)
        if result !== :nomatch
            return result
        end
    end
    return :nomatch
end

function walk(x::Pass, expr_list)
    function patch(expr)
        result = pass(x, expr)
        result === :nomatch ? expr : result
    end
    prewalk.(patch, expr_list)
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#spec>>[3]
#| id: spec
@kwdef struct MixinPass <: Pass
    items::Vector{Symbol}
end

function pass(m::MixinPass, expr)
    @capture(expr, @mixin deps_) || return :nomatch

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
    @assert @capture(mod, module name_
    body__
    end)

    parents = MixinPass([])
    clean_body = walk(parents, body)

    esc(Expr(:toplevel, :(module $name
    $(clean_body...)
    const AST = $body
    const PARENTS = [$(QuoteNode.(parents.items)...)]
    end)))
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#mixin>>[init]
#| id: mixin
macro mixin(deps)
    if @capture(deps, (multiple_deps__,))
        esc(:(const PARENTS = [$(QuoteNode.(multiple_deps)...)]))
    else
        esc(:(const PARENTS = [$(QuoteNode(deps))]))
    end
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#struct-data>>[init]
#| id: struct-data

struct Struct
    use_kwdef::Bool
    is_mutable::Bool
    name::Symbol
    abstract_type::Union{Symbol,Nothing}
    fields::Vector{Union{Expr,Symbol}}
end

function extend_struct!(s1::Struct, s2::Struct)
    append!(s1.fields, s2.fields)
end

function parse_struct(expr)
    @capture(expr, (@kwdef kw_struct_expr_) | struct_expr_)
    uses_kwdef = kw_struct_expr !== nothing
    struct_expr = uses_kwdef ? kw_struct_expr : struct_expr

    @capture(struct_expr, (struct name_
        fields__::Any
    end) | (mutable struct mut_name_
        fields__::Any
    end)) || return

    is_mutable = mut_name !== nothing
    sname = is_mutable ? mut_name : name
    @capture(sname, (name_ <: abst_) | name_)

    return Struct(uses_kwdef, is_mutable, name, abst, fields)
end

function define_struct(s::Struct)
    name = s.abstract_type !== nothing ? :($(s.name) <: $(s.abstract_type)) : s.name
    sdef = if s.is_mutable
        :(mutable struct $name
            $(s.fields...)
        end)
    else
        :(struct $name
            $(s.fields...)
        end)
    end
    s.use_kwdef ? :(@kwdef $sdef) : sdef
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#compose>>[init]
#| id: compose

struct CollectUsingPass <: Pass
    items::Vector{Expr}
end

function pass(p::CollectUsingPass, expr)
    @capture(expr, using x__ | using mod__: x__) || return :nomatch
    push!(p.items, expr)
    return nothing
end

struct CollectConstPass <: Pass
    items::Vector{Expr}
end

function pass(p::CollectConstPass, expr)
    @capture(expr, const x_ = y_) || return :nomatch
    push!(p.items, expr)
    return nothing
end

struct CollectStructPass <: Pass
    items::IdDict{Symbol,Struct}
end

function pass(p::CollectStructPass, expr)
    s = parse_struct(expr)
    s === nothing && return :nomatch
    if s.name in keys(p.items)
        extend_struct!(p.items[s.name], s)
    else
        p.items[s.name] = s
    end
    return nothing
end

macro compose(mod)
    @assert @capture(mod, module name_
    body__
    end)

    mixins = Symbol[]
    parents = MixinPass([])
    usings = CollectUsingPass([])
    consts = CollectConstPass([])
    structs = CollectStructPass(IdDict())

    function mixin(expr)
        parents = MixinPass([])
        pass1 = walk(parents, expr)
        for p in parents.items
            p in mixins && continue
            push!(mixins, p)
            parent_expr = Core.eval(__module__, :($(p).AST))
            mixin(parent_expr)
        end
        walk(usings + consts + structs, pass1)
    end

    clean_body = mixin(body)

    esc(Expr(:toplevel, :(module $name
    $(usings.items...)
    $(consts.items...)
    $(define_struct.(values(structs.items))...)
    $(clean_body...)
    const AST = $body
    const PARENTS = [$(QuoteNode.(parents.items)...)]
    end)))
end
# ~/~ end

end
# ~/~ end
