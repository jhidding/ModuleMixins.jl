# Composition syntax

!!! note "Origin"
    This chapter, including the code in `src/Components/Syntactic.jl`, was written by Claude Opus 5.5 (Anthropic) at the request of Johan Hidding, on 2026-11-04.

The [previous chapter](@ref "Composition by closure") composes models from components through a protocol of ordinary functions, `requires` and `implements`, and composes records from the structs that components define. This chapter adds the `@component` macro, an optional shorthand for that protocol.

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

Inside `@component module Name ... end`:

| Declaration | Expands to |
|---|---|
| `@mixin A, B` | `import ..A, ..B` and `requires(::Val{Name}) = (A, B)` |
| `@requires R` | adds `R` (a role or a component module) to `requires` |
| `@implements R, S` | `implements(::Val{Name}, ::Type{R}) = true`, and the same for `S` |
| a field type mentions struct `S` of the same module | the struct gets a type parameter `S` |

Declarations can be separated by commas or spaces. `@mixin A` imports `A` from the parent module, just like the `@mixin` of `@compose` does. A qualified name, like `@mixin Main.Spring` or `@mixin SomePackage.Spring`, is not imported, and should resolve as written inside the component module. All method definitions refer to `ModuleMixins.Procedural` directly, so a component module needn't import `requires` or `implements`.

The macro also checks for mistakes when the component is defined:

- a `@mixin` has to name a module;
- a `@requires` has to name a module or a type;
- an `@implements` has to name a type.

### Contained records

A record contains another record when the type of one of its fields mentions the other record's struct. The previous chapter requires the containing struct to be parametric, with the parameter named after the contained record (see [Records](@ref)). The macro does this rewrite, so users don't see the type parameter. This works in any struct, not only `Input`. A struct that mentions its own name is a recursive type, not a record containing itself, and is left alone.

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

# expanded
module FaciesBase
    @kwdef struct Facies
        name::String
    end

    @kwdef struct Input{Facies}
        facies::Vector{Facies} = []
    end
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

To find the records a struct contains, collect the names of other structs in the module that appear in its field types. A field is `name::T`, possibly with a default value (`@kwdef`) or marked `const`. Other expressions in the struct body, like inner constructors, are skipped.

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

Adding type parameters to the struct head keeps a supertype in place. `record_type` reads every type parameter as the name of a record, so a struct that contains records can't have type parameters of its own.

```julia
#| id: syntactic-structs
function add_parameters(head, params)
    Meta.isexpr(head, :<:) && return Expr(:<:, add_parameters(head.args[1], params), head.args[2])
    Meta.isexpr(head, :curly) &&
        error("struct $(head.args[1]) contains records, so it can't have type parameters of its own")
    return Expr(:curly, head, params...)
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
```

### Checks

Checks that need the value of a name can't be done during macro expansion, since the name may not be defined yet. They are emitted as function calls at the end of the module, so they run when the module is defined.

```julia
#| id: syntactic-checks
"""
    check_declaration(x, valid, declaration, name)

Check that `x`, named `name` in `declaration`, is an instance of `valid`.
"""
function check_declaration(x, valid, declaration, name)
    x isa valid || error("$(declaration) $(name): expected a $(valid), got $(typeof(x))")
    return nothing
end
```

### The macro

`@component` splits the module body into declarations and other statements, rewrites the structs that contain records, and appends the method definitions. Inside the module, its own name refers to the module, so the methods dispatch on `Val{Name}`. Method names are `GlobalRef`s to `Procedural`, so they extend the protocol functions whatever is in scope in the component module.

```julia
#| id: syntactic-component
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
```

## Tests

The tests repeat the elemental example of the previous chapter, mixing components written with `@component` and by hand. The last part tests records.

```julia
#| file: test/SyntacticSpec.jl
module SyntacticSpec
using Test
using ModuleMixins.Syntactic
using ModuleMixins.Procedural
import ModuleMixins.Procedural: default_implementation, requires

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
    @implements AbstractSource
    @kwdef struct Input
        c::Float64 = 1.0
    end
    value(s::Input, model) = s.c
end

default_implementation(::Type{AbstractSource}) = Constant

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
    requires(::Val{Square}) = (AbstractSource,)
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
    @test requires(Sum) == (Double, Square)
    @test requires(Double) == (AbstractSource,)
    @test implements(Ramp, AbstractGradient)
    @test !implements(Constant, AbstractGradient)
    @test closure(Sum) == (Constant, Double, Square, Sum)

    m = record_type(:Input, Sum)(c = 3.0, factor = 10.0)
    @test value(component(m, Sum.Input), m) == 39.0
    r = record_type(:Input, Sum, Ramp)(slope = 2.0, x = 1.5)
    @test (@inferred value(component(r, Sum.Input), r)) == 15.0
    @test component(r, AbstractGradient) === component(r, AbstractSource)
end

@testset "Syntactic errors" begin
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
    @test_throws ErrorException @eval @component module BadRequirement
        @requires Base.sin
        struct Input end
    end
    @test_throws ErrorException @eval @component module BadRole
        @implements Base.sin
        struct Input end
    end
    @test_throws ErrorException macroexpand(@__MODULE__, :(Syntactic.@mixin Sum))
end

@component module FaciesBase
    @kwdef struct Layer
        thickness::Float64 = 1.0
    end

    @kwdef struct Facies
        name::String
        layers::Vector{Layer} = []
    end

    """
    Input with a docstring and a supertype.
    """
    @kwdef struct Input <: Any
        facies::Vector{Facies} = []
    end

    # recursive, not a record containing itself
    struct Tree
        children::Vector{Tree}
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
    @kwdef mutable struct State
        height::Float64 = 0.0
    end
end

# contributes nothing per facies
@component module Time
    @mixin FaciesBase
    @kwdef struct Input
        t_end::Float64 = 1.0
    end
end

@testset "Syntactic records" begin
    @test FaciesBase.Input isa UnionAll
    @test FaciesBase.Facies isa UnionAll
    @test FaciesBase.Layer isa DataType
    @test FaciesBase.Tree isa DataType

    M = record_type(:Input, Production, Time)
    m = M(facies = [(name = "reef", rate = 2.0, layers = [(thickness = 3.0,)]), (name = "lagoon",)],
          t_end = 5.0)
    @test m.t_end == 5.0
    @test [f.name for f in m.facies] == ["reef", "lagoon"]
    @test [f.rate for f in m.facies] == [2.0, 0.0]
    @test m.facies[1].layers[1].thickness == 3.0
    @test isempty(m.facies[2].layers)
    @test component(m.facies[1], Production) isa Production.Facies
    @test component(m, FaciesBase) isa FaciesBase.Input
    @test (@inferred (m -> m.facies[1].rate)(m)) == 2.0

    S = record_type(:State, Production, Time)
    @test S(height = 1.0).height == 1.0

    # only the base part
    b = record_type(:Input, FaciesBase)(facies = [(name = "a",)])
    @test b.facies[1].name == "a"
    @test_throws ErrorException record_type(:Input, FaciesBase)(facies = [(rate = 1.0,)])
end
end
```

## Example: facies

A small model in the style of CarboKitten. Facies have a name, production adds a rate per facies, and the model computes the total production over all facies. Each component dispatches on its own `Facies` part, while reading other fields through the composite.

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

const Model = record_type(:Input, Production)
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
