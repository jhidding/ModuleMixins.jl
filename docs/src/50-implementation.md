# Implementation
The way `ModuleMixins` is implemented, is that we start out with something relatively simple, and build out from that. This means there will be some redudant code. Macros are hard to engineer, this takes you through the entire process.

## Prelude

```julia
#| file: src/ModuleMixins.jl
module ModuleMixins

using MacroTools: @capture, postwalk, prewalk

export @spec

<<spec>>
<<mixin>>
<<struct-data>>
<<compose>>

end
```

To facilitate testing, we need to be able to compare syntax. We use the `clean` function to remove source information from expressions.

```julia
#| file: test/runtests.jl
using Test
using ModuleMixins: @spec, @spec_mixin, @spec_using, @mixin, Struct, parse_struct, define_struct, Pass
using MacroTools: prewalk, rmlines

clean(expr) = prewalk(rmlines, expr)

<<test-toplevel>>

@testset "ModuleMixins" begin
    <<test>>
end
```

## `@spec`

The `@spec` macro creates a new module, and stores its own AST inside that module.

```julia
#| id: test-toplevel
@spec module MySpec
    const msg = "hello"
end
```

```julia
#| id: test
@testset "@spec" begin
    @test clean.(MySpec.AST) == clean.([:(const msg = "hello")])
    @test MySpec.msg == "hello"
end
```

The `@spec` macro is used to specify the structs of a model component.

```julia
#| id: spec
"""
    @spec module *name*
        *body*...
    end

Create a spec. The `@spec` macro itself doesn't perform any operations other than creating a module and storing its own AST as `const *name*.AST`.
"""
macro spec(mod)
    @assert @capture(mod, module name_ body__ end)

    esc(Expr(:toplevel, :(module $name
        $(body...)
        const AST = $body
    end)))
end
```

### `@spec_mixin`

We now add the `@mixin` syntax. This still doesn't do anything, other than storing the names of parent modules.

```julia
#| id: test-toplevel
@spec_mixin module MyMixinSpecOne
    @mixin A
end
@spec_mixin module MyMixinSpecMany
    @mixin A, B, C
end
```

```julia
#| id: test
@testset "@spec_mixin" begin
    @test MyMixinSpecOne.PARENTS == [:A]
    @test MyMixinSpecMany.PARENTS == [:A, :B, :C]
end
```

Here's the `@mixin` macro:

```julia
#| id: mixin
macro mixin(deps)
    if @capture(deps, (multiple_deps__,))
        esc(:(const PARENTS = [$(QuoteNode.(multiple_deps)...)]))
    else
        esc(:(const PARENTS = [$(QuoteNode(deps))]))
    end
end
```

The `QuoteNode` calls prevent the symbols from being evaluated at macro expansion time. We need to make sure that the `@mixin` syntax is also available from within the module.

```julia
#| id: spec

macro spec_mixin(mod)
    @assert @capture(mod, module name_ body__ end)

    esc(Expr(:toplevel, :(module $name
        import ..@mixin

        $(body...)

        const AST = $body
    end)))
end
```

### `@spec_using`

I can't think of any usecase where a `@mixin A`, doesn't also mean `using ..A`. By replacing the `@mixin` with a `using` statement, we also no longer need to import `@mixin`. In fact, that macro becomes redundant. Also, in `@spec_using` we're allowed multiple `@mixin` statements.

```julia
#| id: test-toplevel
@spec_using module SU_A
    const X = :hello
    export X
end

@spec_using module SU_B
    @mixin SU_A
    const Y = X
end

@spec_using module SU_C
    const Z = :goodbye
end

@spec_using module SU_D
    @mixin SU_A
    @mixin SU_B, SU_C
end
```

```julia
#| id: test
@testset "@spec_using" begin
    @test SU_B.Y == SU_A.X
    @test SU_B.PARENTS == [:SU_A]
    @test SU_D.PARENTS == [:SU_A, :SU_B, :SU_C]
    @test SU_D.SU_C.Z == :goodbye
end
```

We now use the `postwalk` function (from `MacroTools.jl`) to transform expressions and collect information into searchable data structures. We make a little abstraction over the `postwalk` function, so we can compose multiple transformations in a single tree walk.

```julia
#| id: test-toplevel
struct EmptyPass <: Pass
    tag::Symbol
end
```

```julia
#| id: test
@testset "pass composition" begin
    a = EmptyPass(:a) + EmptyPass(:b)
    @test a.parts[1].tag == :a
    @test a.parts[2].tag == :b
end
```

A composite pass tries all of its parts in order, returning the value of the first pass that doesn't return `nothing`.

```julia
#| id: spec

abstract type Pass end

function pass(x::Pass, expr)
    error("Can't call `pass` on abstract `Pass`.")
end

struct CompositePass <: Pass
    parts::Vector{Pass}
end

Base.:+(a::CompositePass...) =
    CompositePass(splat(vcat)(getfield.(a, :parts)))
Base.convert(::Type{CompositePass}, a::Pass) =
    CompositePass([a])
Base.:+(a::Pass...) = splat(+)(convert.(CompositePass, a))

function pass(cp::CompositePass, expr)
    for p in cp.parts
        result = pass(p, expr)
        if result !== nothing
            return result
        end
    end
end

function walk(x::Pass, expr_list)
    function patch(expr)
        result = pass(x, expr)
        result == nothing ? expr : result
    end
    postwalk.(patch, expr_list)
end
```

```julia
#| id: spec
@kwdef struct MixinPass <: Pass
    parents::Vector{Symbol}
end

function pass(m::MixinPass, expr)
    @capture(expr, @mixin deps_) || return

    if @capture(deps, (multiple_deps__,))
        append!(m.parents, multiple_deps)
        :(begin $([:(using ..$d) for d in multiple_deps]...) end)
    else
        push!(m.parents, deps)
        :(using ..$deps)
    end
end

macro spec_using(mod)
    @assert @capture(mod, module name_ body__ end)

    p = MixinPass([])
    clean_body = walk(p, body)

    esc(Expr(:toplevel, :(module $name
        $(clean_body...)
        const AST = $body
        const PARENTS = [$(QuoteNode.(p.parents)...)]
    end)))
end
```

## Structure of structs

We'll convert `struct` syntax into collectable data, then convert that back into structs again. We'll support several patterns:

```julia
#| id: test
cases = Dict(
    :(struct A x end) => Struct(false, false, :A, nothing, [:x]),
    :(mutable struct A x end) => Struct(false, true, :A, nothing, [:x]),
    :(@kwdef struct A x end) => Struct(true, false, :A, nothing, [:x]),
    :(@kwdef mutable struct A x end) => Struct(true, true, :A, nothing, [:x]))

for (k, v) in pairs(cases)
    @testset "Struct mangling: $(join(split(string(clean(k))), " "))" begin
        @test clean(define_struct(parse_struct(k))) == clean(k)
        @test clean(define_struct(v)) == clean(k)
    end
end
```

Each of these can have either just a `Symbol` for a name, or a `A <: B` expression. This is a bit cumbersome, but we'll have to deal with all of these cases.

```julia
#| id: test
@testset "Struct mangling abstracts" begin
    @test parse_struct(:(struct A <: B x end)).abstract_type == :B
    @test parse_struct(:(mutable struct A <: B x end)).abstract_type == :B
end
```

```julia
#| id: struct-data

struct Struct
    use_kwdef::Bool
    is_mutable::Bool
    name::Symbol
    abstract_type::Union{Symbol, Nothing}
    fields::Vector{Union{Expr,Symbol}}
end

function parse_struct(expr)
    @capture(expr, (@kwdef kw_struct_expr_) | struct_expr_)
    uses_kwdef = kw_struct_expr !== nothing
    struct_expr = uses_kwdef ? kw_struct_expr : struct_expr

    @capture(struct_expr,
        (struct name_ fields__ end) |
        (mutable struct mut_name_ fields__ end)) || return

    is_mutable = mut_name !== nothing
    sname = is_mutable ? mut_name : name
    @capture(sname, (name_ <: abst_) | name_)

    return Struct(uses_kwdef, is_mutable, name, abst, fields)
end

function define_struct(s::Struct)
    name = s.abstract_type !== nothing ?
        :($(s.name) <: $(s.abstract_type)) :
        s.name
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
```

## `@compose`

Unfortunately now comes a big leap. We'll merge all struct definitions inside the body of a module definition with that of its parents. We must also make sure that a `struct` definition still compiles, so we have to take along `using` and `const` statements.

```julia
#| id: compose

struct CollectUsingPass <: Pass
    imports::Vector{Expr}
end

function pass(p::CollectUsingPass, expr)
    @capture(expr, using x__ | using mod__: x__) || return
    push!(p.imports, expr)
    return expr
end

struct CollectConstPass <: Pass
    consts::Vector{Expr}
end

function pass(p::CollectConstPass, expr)
    @capture(expr, const x_ = y_) || return
    push!(p.consts, expr)
    return expr
end

struct CollectStructPass <: Pass
    structs::Vector{Struct}
end

function pass(p::CollectStructPass, expr)
    s = parse_struct(expr)
    s === nothing && return
    push!(p.structs, s)
    return expr
end

macro compose(mod)
    @assert @capture(mod, module name_ body__ end)

    p = MixinPass([])
    clean_body = walk(p, body)

    esc(Expr(:toplevel, :(module $name
        $(clean_body...)
        const AST = $body
        const PARENTS = [$(QuoteNode.(p.parents)...)]
    end)))
end
```

## `@compose`

The idea of `@compose` is that it splices `struct` definitions, such that resulting structs contain all members from required specs.

We define some variables to collect structs, consts and `using` declarations. At the end we use these collections to build a new module.

``` {.julia #dsl-spec-defs}
@spec A begin
  struct S
    a::Int
  end
end

@spec B begin
  struct S
    b::Int
  end
end

@compose AB [A, B] begin
end
```

``` {.julia #dsl-spec}
@test fieldnames(AB.S) == (:a, :b)
```

A spec can depend on another using the `@require` syntax.

``` {.julia #dsl-spec-defs}
@spec C begin
  @requires A
  struct S
    c::Int
  end

  @kwdef struct T
    f::Int
  end
end

@compose AC [C] begin
end
```

``` {.julia #dsl-spec}
@test fieldnames(AC.S) == (:a, :c)
@test fieldnames(AC.T) == (:f,)
@test AC.T(f = 4).f == 4
```

```@raw html
<details><summary>`@compose` implementation</summary>
```

``` {.julia #dsl}
macro compose(modname, cs, body)
    components = Set{Symbol}()

    structs = IdDict()
    using_statements = []
    const_statements = []
    specs_used = Set()

    <<dsl-compose>>

    @assert cs.head == :vect
    cs.args .|> scan

    Expr(:toplevel, esc(:(module $modname
        $(using_statements...)
        $(const_statements...)
        $(Iterators.map(splat(define_struct), pairs(structs))...)
        $(body.args...)
    end)))
end
```

``` {.julia #dsl-compose}
function extend_struct!(name::Symbol, fields::Vector)
    append!(structs[name].fields, fields)
end

function create_struct!(name::Symbol, is_mutable::Bool, is_kwarg::Bool, abst::Union{Symbol, Nothing}, fields::Vector)
    structs[name] = Struct(is_mutable, is_kwarg, abst, fields)
end

function pass(e)
    if @capture(e, @requires parents__)
        parents .|> scan
        return
    end

    if @capture(e, (struct name_ fields__ end) |
                   (@kwdef struct kw_name_ fields__ end) |
                   (mutable struct mut_name_ fields__ end))
        is_mutable = mut_name !== nothing
        is_kwarg = kw_name !== nothing
        sname = is_mutable ? mut_name : (is_kwarg ? kw_name : name)

        @capture(sname, (name_ <: abst_) | name_)

        if name in keys(structs)
            extend_struct!(name, fields)
        else
            create_struct!(name, is_mutable, is_kwarg, abst, fields)
        end
        return
    end

    if @capture(e, const n_ = x_)
        push!(const_statements, e)
        return
    end

    if @capture(e, using x__ | using mod__: x__)
        push!(using_statements, e)
        return
    end

    return e
end

function scan(c::Symbol)
    if c in specs_used
        return
    end
    push!(specs_used, c)

    e = Core.eval(__module__, :($(c).AST))
    prewalk(pass, e)
end
```

``` {.julia #dsl-struct-type}
struct Struct
    mut::Bool
    kwarg::Bool
    parent::Union{Symbol, Nothing}
    fields::Vector{Union{Expr,Symbol}}
end

function define_struct(name::Symbol, s::Struct)
    if s.parent !== nothing
        name = :($name <: $(s.parent))
    end
    if s.mut
        :(mutable struct $name
            $(s.fields...)
        end)
    elseif s.kwarg
        :(@kwdef struct $name
            $(s.fields...)
          end)
    else
        :(struct $name
            $(s.fields...)
        end)
    end
end
```

```@raw html
</details>
```
