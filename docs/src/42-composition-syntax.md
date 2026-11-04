# Composition syntax

!!! note "Origin"
    This chapter, including the code in `src/Components/Syntactic.jl`, was written by Claude Opus 5.5 (Anthropic) at the request of Johan Hidding, on 2026-11-04.

The [previous chapter](@ref "Composition by closure") composes models from components through a protocol of ordinary functions: `requires`, `implements`, `item_collection` and `item_part`. This chapter adds the `@component` macro, an optional shorthand for that protocol, as proposed in [A local, module-level macro](@ref).

```julia
@component module Spring
    @mixin Time
    @implements AbstractOscillator

    @kwdef struct Input
        spring_constant::Float64
    end
end
```

The macro differs from `@compose` in one important way: it is purely local. It reads only the module it's applied to, and expands to that module plus a few method definitions. It never inspects or re-evaluates code from other modules. A component written by hand, like `Damping` in the previous chapter, works alongside components written with `@component`.

## Syntax

Inside a `@component` module:

| Declaration | Expands to |
|---|---|
| `@mixin A, B` | `import ..A, ..B` and `requires(::Type{<:Input}) = (A.Input, B.Input)` |
| `@requires R` | adds `R` (a role or a component type) to `requires` |
| `@implements R, S` | `implements(::Type{<:Input}, ::Type{R}) = true`, and the same for `S` |
| `struct Facies` | `item_part(::Type{<:Input}, ::Val{:Facies}) = Facies` |
| `facies::Vector{Facies}` in `Input` | `Input` gets a type parameter `Facies`, and `item_collection(::Type{<:Input}) = (:Facies,)` |

Declarations can be separated by commas or spaces. `@mixin A` imports `A` from the parent module, just like the `@mixin` of `@compose` does. A qualified name, like `@mixin Main.Spring` or `@mixin SomePackage.Spring`, is not imported, and should resolve as written inside the component module. All method definitions refer to `ModuleMixins.Procedural` directly, so a component module needn't import `requires` or `implements`.

The macro also checks for mistakes when the component is defined:

- the module has to define a struct `Input`;
- a `@mixin` has to name a module that defines `Input`;
- a `@requires` or `@implements` has to name a type.

### Item structs

Every struct in a component module other than `Input` is a candidate item part. The macro declares it with `item_part`, keyed by the struct's name. That is harmless for structs that are never used as items, like a `State`: nothing asks for them.

If the field types of `Input` mention one of these structs by name, that name becomes a type parameter of `Input`. This changes the meaning of `Facies` inside `Input`: it now stands for the composite of all `Facies` parts in the model. `model_type` substitutes that composite (see [Per-item records](@ref)), so users never see the parameter.

```julia
# written
@component module FaciesBase
    @kwdef struct Facies
        name::String
    end

    @kwdef struct Input
        facies::Vector{Facies} = []
    end
end

# expanded (roughly)
module FaciesBase
    @kwdef struct Facies
        name::String
    end

    @kwdef struct Input{Facies}
        facies::Vector{Facies} = []
    end

    Procedural.item_collection(::Type{<:Input}) = (:Facies,)
    Procedural.item_part(::Type{<:Input}, ::Val{:Facies}) = Facies
end
```

A component that adds per-facies fields only needs to define its own `struct Facies`. Components that don't contribute to the facies define no such struct.

## Implementation

!!! details "src/Components/Syntactic.jl"

    ```julia
    #| file: src/Components/Syntactic.jl
    module Syntactic

    using ..Common: strip_syntax_version
    import ..Procedural

    export @component

    <<syntactic-declarations>>
    <<syntactic-structs>>
    <<syntactic-checks>>
    <<syntactic-component>>

    end
    ```

### Declarations

A declaration is a macro call at the top level of the module body. The macros `@mixin`, `@requires` and `@implements` are never expanded: `@component` sees the body before expansion, and removes them. They are defined only to give a helpful error when used elsewhere.

```julia
#| id: syntactic-declarations
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
```

### Structs

Structs may be wrapped in macro calls, like `@kwdef` or a docstring. `map_struct` looks through those, and applies a function to the struct definition. Only the top level of the module body is searched.

```julia
#| id: syntactic-structs
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
```

To find the item kinds of `Input`, collect the names of item structs that appear in its field types. A field is `name::T`, possibly with a default value (`@kwdef`) or marked `const`. Other expressions in the struct body, like inner constructors, are skipped.

```julia
#| id: syntactic-structs
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
```

Adding type parameters to the struct head keeps a supertype in place. If `Input` already has type parameters, adding more would make the order ambiguous, so that is an error.

```julia
#| id: syntactic-structs
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
```

### Checks

Checks that need the value of a name can't be done during macro expansion, since the name may not be defined yet. They are emitted as function calls at the end of the module, so they run when the module is defined.

```julia
#| id: syntactic-checks
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
```

### The macro

`@component` splits the module body into declarations and other statements, finds the structs, rewrites `Input`, and appends the method definitions. Method names are `GlobalRef`s to `Procedural`, so they extend the protocol functions whatever is in scope in the component module.

```julia
#| id: syntactic-component
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
```

## Tests

The tests repeat the elemental example of the previous chapter, mixing components written with `@component` and by hand. The last part tests per-item records.

```julia
#| file: test/SyntacticSpec.jl
module SyntacticSpec
using Test
using ModuleMixins.Syntactic
using ModuleMixins.Procedural
import ModuleMixins.Procedural: default_implementation, requires, item_part

abstract type AbstractSource end
abstract type AbstractGradient end
function value end
function gradient end

@component module Ramp
    import ..AbstractSource, ..AbstractGradient, ..value, ..gradient
    @implements AbstractSource, AbstractGradient
    @kwdef struct Input
        slope::Float64 = 1.0
        x::Float64 = 0.0
    end
    value(s::Input, model) = s.slope * s.x
    gradient(s::Input, model) = s.slope
end

@component module Constant
    import ..AbstractSource, ..value
    @kwdef struct Input <: AbstractSource
        c::Float64 = 1.0
    end
    value(s::Input, model) = s.c
end

default_implementation(::Type{AbstractSource}) = Constant.Input

@component module Double
    import ..AbstractSource, ..value
    using ModuleMixins.Procedural: component
    @requires AbstractSource
    @kwdef struct Input
        factor::Float64 = 2.0
    end
    value(d::Input, model) = d.factor * value(component(model, AbstractSource), model)
end

# written by hand
module Square
    import ..AbstractSource, ..value, ..requires
    using ModuleMixins.Procedural: component
    struct Input end
    requires(::Type{Input}) = (AbstractSource,)
    value(::Input, model) = value(component(model, AbstractSource), model)^2
end

@component module Sum
    import ..value
    using ModuleMixins.Procedural: component
    @mixin Double Square
    struct Input end
    value(::Input, model) =
        value(component(model, Double.Input), model) +
        value(component(model, Square.Input), model)
end

@testset "Syntactic" begin
    @test requires(Sum.Input) == (Double.Input, Square.Input)
    @test requires(Double.Input) == (AbstractSource,)
    @test implements(Ramp.Input, AbstractGradient)
    @test closure(Sum.Input) == (Constant.Input, Double.Input, Square.Input, Sum.Input)

    m = model_type(Sum.Input)(c = 3.0, factor = 10.0)
    @test value(component(m, Sum.Input), m) == 39.0
    r = model_type(Sum.Input, Ramp.Input)(slope = 2.0, x = 1.5)
    @test (@inferred value(component(r, Sum.Input), r)) == 15.0
    @test component(r, AbstractGradient) === component(r, AbstractSource)

    # items are never declared for `Input` itself
    @test item_part(Ramp.Input, Val(:Input)) === nothing
end

@testset "Syntactic errors" begin
    @test_throws ErrorException macroexpand(@__MODULE__, :(@component module NoInput
        struct State end
    end))
    @test_throws ErrorException macroexpand(@__MODULE__, :(@component struct Input end))
    @test_throws ErrorException macroexpand(@__MODULE__, :(@component module Parametric
        struct Facies end
        struct Input{T}
            facies::Vector{Facies}
        end
    end))
    @test_throws ErrorException @eval @component module BadMixin
        @mixin AbstractSource
        struct Input end
    end
    @test_throws ErrorException @eval @component module BadRole
        @implements Base.sin
        struct Input end
    end
    @test_throws ErrorException macroexpand(@__MODULE__, :(Syntactic.@mixin Sum))
end

@component module FaciesBase
    @kwdef struct Facies
        name::String
    end

    """
    Input with a documented field type.
    """
    @kwdef struct Input <: Any
        facies::Vector{Facies} = []
    end
end

@component module Production
    @mixin FaciesBase
    @kwdef struct Facies
        rate::Float64 = 0.0
    end
    @kwdef struct Input
        sea_level::Float64 = 0.0
    end
    mutable struct State
        height::Float64
    end
end

# contributes nothing per item
@component module Time
    @mixin FaciesBase
    @kwdef struct Input
        t_end::Float64 = 1.0
    end
end

@testset "Syntactic items" begin
    @test item_collection(FaciesBase.Input) == (:Facies,)
    @test item_part(Production.Input, Val(:Facies)) === Production.Facies
    @test item_part(Production.Input, Val(:State)) === Production.State
    @test item_part(Time.Input, Val(:Facies)) === nothing

    M = model_type(Production.Input, Time.Input)
    m = M(facies = [(name = "reef", rate = 2.0), (name = "lagoon",)], t_end = 5.0)
    @test m.t_end == 5.0
    @test [f.name for f in m.facies] == ["reef", "lagoon"]
    @test [f.rate for f in m.facies] == [2.0, 0.0]
    @test component(m.facies[1], Production.Facies) isa Production.Facies
    @test component(m, FaciesBase.Input) isa FaciesBase.Input
    @test (@inferred (m -> m.facies[1].rate)(m)) == 2.0

    # only the base part
    b = model_type(FaciesBase.Input)(facies = [(name = "a",)])
    @test b.facies[1].name == "a"
    @test_throws ErrorException model_type(FaciesBase.Input)(facies = [(rate = 1.0,)])
end
end
```

## Example: facies

A small model in the style of CarboKitten. Facies have a name, production adds a rate per facies, and the model computes the total production over all facies. The `Production` component dispatches on its own `Facies` part, while reading the shared name through the composite.

```julia
#| file: examples/composition/facies.jl
using ModuleMixins.Syntactic
using ModuleMixins.Procedural

function describe end

@component module FaciesBase
    import ..describe
    @kwdef struct Facies
        name::String
    end
    @kwdef struct Input
        facies::Vector{Facies} = []
    end
    describe(f::Facies, item) = "facies $(f.name)"
end

@component module Production
    import ..describe
    @mixin FaciesBase
    @kwdef struct Facies
        rate::Float64 = 0.0
    end
    @kwdef struct Input
        scale::Float64 = 1.0
    end
    describe(f::Facies, item) = "produces $(f.rate)"
    total(input) = input.scale * sum(f.rate for f in input.facies)
end

const Model = model_type(Production.Input)
m = Model(scale = 2.0, facies = [(name = "reef", rate = 3.0), (name = "lagoon", rate = 1.0)])
@show Production.total(m)
for f in m.facies
    println(join((describe(p, f) for p in parts(f)), ", "))
end
```

```
Production.total(m) = 8.0
facies reef, produces 3.0
facies lagoon, produces 1.0
```
