# ~/~ begin <<docs/src/42-composition-syntax.md#src/Components/Syntactic.jl>>[init]
module Syntactic

using ..Common: strip_syntax_version
import ..Procedural

export @component

# ~/~ begin <<docs/src/42-composition-syntax.md#syntactic-declarations>>[init]
const DECLARATIONS = (Symbol("@mixin"), Symbol("@requires"), Symbol("@implements"))

"""
    declaration(expr)

If `expr` is one of the declarations `@mixin`, `@requires` or `@implements`,
return the declaration name and its arguments. Otherwise return `nothing`.
Arguments may be separated by spaces or by commas.
"""
function declaration(expr)
    Meta.isexpr(expr, :macrocall) && expr.args[1] in DECLARATIONS || return nothing
    args = [a for a in expr.args[2:end] if !(a isa LineNumberNode)]
    args = collect(Iterators.flatten(Meta.isexpr(a, :tuple) ? a.args : (a,) for a in args))
    return expr.args[1] => args
end

"""
    @mixin Components...

Declaration inside a `@component` module. See [`@component`](@ref).
"""
macro mixin(args...)
    error("`@mixin` can only be used inside a `@component` module")
end

"""
    @requires Types...

Declaration inside a `@component` module. See [`@component`](@ref).
"""
macro requires(args...)
    error("`@requires` can only be used inside a `@component` module")
end

"""
    @implements Roles...

Declaration inside a `@component` module. See [`@component`](@ref).
"""
macro implements(args...)
    error("`@implements` can only be used inside a `@component` module")
end
# ~/~ end
# ~/~ begin <<docs/src/42-composition-syntax.md#syntactic-structs>>[init]
"""
    map_struct(f, expr)

Apply `f` to the struct definition in `expr`, looking through macro calls
like `@kwdef` and docstrings. Returns `expr` unchanged if it doesn't define
a struct.
"""
function map_struct(f, expr)
    Meta.isexpr(expr, :struct) && return f(expr)
    Meta.isexpr(expr, :macrocall) || return expr
    return Expr(:macrocall, (map_struct(f, a) for a in expr.args)...)
end

"""
    struct_name(expr)

The name of the struct defined by `expr`, or `nothing`.
"""
function struct_name(expr)
    result = nothing
    map_struct(s -> (result = type_name(s.args[2]); s), expr)
    return result
end

type_name(head) =
    Meta.isexpr(head, :<:) ? type_name(head.args[1]) :
    Meta.isexpr(head, :curly) ? head.args[1] :
    head
# ~/~ end
# ~/~ begin <<docs/src/42-composition-syntax.md#syntactic-structs>>[1]
"""
    field_types(struct_expr)

The declared types of the fields of a struct.
"""
function field_types(expr)
    types = []
    for field in expr.args[3].args
        Meta.isexpr(field, :const) && (field = field.args[1])
        Meta.isexpr(field, :(=)) && (field = field.args[1])
        Meta.isexpr(field, :(::)) && length(field.args) == 2 && push!(types, field.args[2])
    end
    return types
end

"""
    mentioned(names, expr)

The elements of `names` that occur as a symbol anywhere in `expr`, in the
order of `names`.
"""
function mentioned(names, expr)
    found = Set{Symbol}()
    visit(x) = x isa Symbol ? push!(found, x) : x isa Expr && foreach(visit, x.args)
    visit(expr)
    return [n for n in names if n in found]
end
# ~/~ end
# ~/~ begin <<docs/src/42-composition-syntax.md#syntactic-structs>>[2]
function add_parameters(head, params)
    Meta.isexpr(head, :<:) && return Expr(:<:, add_parameters(head.args[1], params), head.args[2])
    Meta.isexpr(head, :curly) &&
        error("`Input` has per-item fields, so it can't have type parameters of its own")
    return Expr(:curly, head, params...)
end

"""
    parameterize_input(expr, item_names)

Rewrite the definition of `Input` in `expr`, so that every item struct in
`item_names` that is mentioned in a field type becomes a type parameter.
Returns the new expression and the item kinds, in parameter order.
"""
function parameterize_input(expr, item_names)
    kinds = Symbol[]
    new_expr = map_struct(expr) do s
        append!(kinds, mentioned(item_names, Expr(:block, field_types(s)...)))
        isempty(kinds) && return s
        return Expr(:struct, s.args[1], add_parameters(s.args[2], kinds), s.args[3])
    end
    return new_expr, kinds
end
# ~/~ end
# ~/~ begin <<docs/src/42-composition-syntax.md#syntactic-checks>>[init]
"""
    check_mixin(m, name)

Check that `m`, named `name` in a `@mixin`, is a component module.
"""
function check_mixin(m, name)
    m isa Module || error("@mixin $(name): not a module")
    isdefined(m, :Input) || error("@mixin $(name): module doesn't define `Input`, so it isn't a component")
    return nothing
end

"""
    check_type(T, declaration, name)

Check that `T`, named `name` in `declaration`, is a type.
"""
function check_type(T, declaration, name)
    T isa Type || error("$(declaration) $(name): not a type")
    return nothing
end
# ~/~ end
# ~/~ begin <<docs/src/42-composition-syntax.md#syntactic-component>>[init]
mixin_import(m::Symbol) = [Expr(:import, Expr(:., :., :., m))]
mixin_import(_) = []

"""
    @component module Name
        [@mixin Components...]
        [@requires Types...]
        [@implements Roles...]
        struct Input ... end
        ...
    end

Define a component module. The module must define a struct `Input`. The
declarations expand into methods of `ModuleMixins.Procedural`:

- `@mixin A, B`: import `A` and `B` from the parent module (if they are plain
  names), and require their `Input` components.
- `@requires R`: require role or component type `R`.
- `@implements R`: `Input` implements role `R`.

Every other struct `S` in the module is declared as the part this component
contributes to items of kind `S` (`item_part`). If a field type of `Input`
mentions such a struct, `Input` gets a type parameter in its place, which
`model_type` fills with the composite of all parts of that kind
(`item_collection`).
"""
macro component(mod)
    mod = strip_syntax_version(mod)
    Meta.isexpr(mod, :module) || error("@component expects a module definition")
    bare, name, body = mod.args

    mixins, requirements, roles, statements = [], [], [], []
    for expr in body.args
        decl = declaration(expr)
        if decl === nothing
            push!(statements, expr)
        elseif decl.first === Symbol("@mixin")
            append!(mixins, decl.second)
        elseif decl.first === Symbol("@requires")
            append!(requirements, decl.second)
        else
            append!(roles, decl.second)
        end
    end

    struct_names = filter(!isnothing, struct_name.(statements))
    :Input in struct_names || error("@component $(name): module doesn't define a struct `Input`")
    item_names = filter(!=(:Input), struct_names)

    kinds = Symbol[]
    statements = map(statements) do expr
        struct_name(expr) === :Input || return expr
        new_expr, k = parameterize_input(expr, item_names)
        append!(kinds, k)
        return new_expr
    end

    P(f) = GlobalRef(Procedural, f)
    S(f) = GlobalRef(@__MODULE__, f)
    input = :(::Type{<:Input})
    requirement_list = [[:($m.Input) for m in mixins]; requirements]

    definitions = [
        (:($(S(:check_mixin))($m, $(QuoteNode(m)))) for m in mixins)...,
        (:($(S(:check_type))($r, "@requires", $(QuoteNode(r)))) for r in requirements)...,
        (:($(S(:check_type))($r, "@implements", $(QuoteNode(r)))) for r in roles)...,
        (isempty(requirement_list) ? () : (:($(P(:requires))($input) = ($(requirement_list...),)),))...,
        (:($(P(:implements))($input, ::Type{$r}) = true) for r in roles)...,
        (isempty(kinds) ? () : (:($(P(:item_collection))($input) = $(Tuple(kinds))),))...,
        (:($(P(:item_part))($input, ::Val{$(QuoteNode(s))}) = $s) for s in item_names)...,
    ]

    new_body = Expr(:block,
        Iterators.flatten(mixin_import.(mixins))...,
        statements...,
        definitions...)
    return esc(Expr(:toplevel, Expr(:module, bare, name, new_body)))
end
# ~/~ end

end
# ~/~ end
