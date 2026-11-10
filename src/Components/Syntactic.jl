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
    @requires Requirements...

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
parameter_name(p) = Meta.isexpr(p, :<:) || Meta.isexpr(p, :>:) ? p.args[1] : p

function add_parameters(head, params)
    Meta.isexpr(head, :<:) && return Expr(:<:, add_parameters(head.args[1], params), head.args[2])
    Meta.isexpr(head, :curly) || return Expr(:curly, head, params...)
    own = parameter_name.(head.args[2:end])
    return Expr(:curly, head.args..., filter(!in(own), params)...)
end

"""
    parameterize(expr, struct_names)

Rewrite the struct defined in `expr` (if any), so that every other struct in
`struct_names` that is mentioned in a field type becomes a type parameter.
"""
parameterize(expr, struct_names) = map_struct(expr) do s
    own = type_name(s.args[2])
    contained = mentioned(filter(!=(own), struct_names), Expr(:block, field_types(s)...))
    isempty(contained) && return s
    return Expr(:struct, s.args[1], add_parameters(s.args[2], contained), s.args[3])
end
# ~/~ end
# ~/~ begin <<docs/src/42-composition-syntax.md#syntactic-checks>>[init]
"""
    check_declaration(x, valid, declaration, name)

Check that `x`, named `name` in `declaration`, is an instance of `valid`.
"""
function check_declaration(x, valid, declaration, name)
    x isa valid || error("$(declaration) $(name): expected a $(valid), got $(typeof(x))")
    return nothing
end
# ~/~ end
# ~/~ begin <<docs/src/42-composition-syntax.md#syntactic-component>>[init]
mixin_import(m::Symbol) = [Expr(:import, Expr(:., :., :., m))]
mixin_import(_) = []

"""
    @component module Name
        [@mixin Components...]
        [@requires Requirements...]
        [@implements Roles...]
        ...
    end

Define a component module. The declarations expand into methods of
`ModuleMixins.Procedural`:

- `@mixin A, B`: import `A` and `B` from the parent module (if they are plain
  names), and require them as components.
- `@requires R`: require role or component `R`.
- `@implements R`: the component implements role `R`.

If a field type of a struct mentions another struct `S` of the same module,
the struct gets a type parameter `S`, which `record_type` fills with the
composite of all parts of record `S`.
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
    statements = map(expr -> parameterize(expr, struct_names), statements)

    P(f) = GlobalRef(Procedural, f)
    check(x, valid, decl) =
        :($(GlobalRef(@__MODULE__, :check_declaration))($x, $valid, $decl, $(QuoteNode(x))))
    self = :(::$(GlobalRef(Base, :Val)){$name})
    requirement_list = [mixins; requirements]

    definitions = [
        (check(m, Module, "@mixin") for m in mixins)...,
        (check(r, Union{Module, Type}, "@requires") for r in requirements)...,
        (check(r, Type, "@implements") for r in roles)...,
        (isempty(requirement_list) ? () : (:($(P(:requires))($self) = ($(requirement_list...),)),))...,
        (:($(P(:implements))($self, ::Type{$r}) = true) for r in roles)...,
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
