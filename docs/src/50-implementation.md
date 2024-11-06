# Implementation

The way `ModuleMixins` is implemented, is that we start out with something relatively simple, and build out from that. This means there will be some redudant code. Macros are hard to engineer, this takes you through the entire process.

## Prelude

```julia
#| file: src/ModuleMixins.jl
module ModuleMixins

using MacroTools: @capture, postwalk, prewalk

export @compose, @for_each

<<spec>>
<<mixin>>
<<struct-data>>
<<compose>>
<<for-each>>

end
```

To facilitate testing, we need to be able to compare syntax. We use the `clean` function to remove source information from expressions.

```julia
#| file: test/runtests.jl
using Test
using ModuleMixins:
    @spec,
    @spec_mixin,
    @spec_using,
    @mixin,
    Struct,
    parse_struct,
    define_struct,
    Pass,
    @compose,
    @for_each
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

This macro is only here for teaching purposes.
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
    @assert @capture(mod, module name_
    body__
    end)

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
```

```julia
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
    @assert @capture(mod, module name_ body__ end)

    parents = MixinPass([])
    clean_body = walk(parents, body)

    esc(Expr(:toplevel, :(module $name
        $(clean_body...)
        const AST = $body
        const PARENTS = [$(QuoteNode.(parents.items)...)]
    end)))
end
```

## Structure of structs

We'll convert `struct` syntax into collectable data, then convert that back into structs again. We'll support several patterns:

```julia
#| id: test
cases = Dict(
    :(struct A x end) => Struct(false, false, :A, nothing, nothing, [:x]),
    :(mutable struct A x end) => Struct(false, true, :A, nothing, nothing, [:x]),
    :(@kwdef struct A x end) => Struct(true, false, :A, nothing, nothing, [:x]),
    :(@kwdef mutable struct A x end) => Struct(true, true, :A, nothing, nothing, [:x]),
    :(struct A{T} x::T end) => Struct(false, false, :A, [:T], nothing, [:(x::T)]),
)

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

@testset "Mangling type arguments" begin
    using ModuleMixins: mangle_type_parameters!
    let s = parse_struct(:(struct S{T} x::T end))
        @test s.type_parameters == [:T]
        mangle_type_parameters!(s, :A)
        @test s.type_parameters == [:_T_A]
        @test clean(define_struct(s)) == clean(:(struct S{_T_A} x::_T_A end))
    end
    let s = parse_struct(:(struct S{T} x::Vector{T} = [] end))
        mangle_type_parameters!(s, :A)
        @test clean(define_struct(s)) == clean(:(struct S{_T_A} x::Vector{_T_A} = [] end))
    end
end
```

```julia
#| id: struct-data

mutable struct Struct
    use_kwdef::Bool
    is_mutable::Bool
    name::Symbol
    type_parameters::Union{Vector{Symbol},Nothing}
    abstract_type::Union{Symbol,Nothing}
    fields::Vector{Union{Expr,Symbol}}
end

function mangle_type_parameters!(s::Struct, suffix::Symbol)
    s.type_parameters === nothing && return

    d = IdDict{Symbol, Symbol}(
        (k => Symbol("_$(k)_$(suffix)") for k in s.type_parameters)...)

    replace_type_par(expr) =
        postwalk(x -> x isa Symbol ? get(d, x, x) : x, expr)
        
    s.fields = replace_type_par.(s.fields)
    s.type_parameters = collect(values(d))
    return s
end

function mappend(a::Union{Vector{T}, Nothing}, b::Union{Vector{T}, Nothing}) where T
    isnothing(a) && return b
    isnothing(b) && return a
    return vcat(a, b)
end

function extend_struct!(s1::Struct, s2::Struct)
    append!(s1.fields, s2.fields)
    s1.type_parameters = mappend(s1.type_parameters, s2.type_parameters)
    return s1
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
    @capture(sname, (pname_ <: abst_) | pname_)
    @capture(pname, (name_{pars__}) | name_)


    return Struct(uses_kwdef, is_mutable, name, pars, abst, fields)
end

function define_struct(s::Struct)
    name = s.type_parameters !== nothing ? :($(s.name){$(s.type_parameters...)}) : s.name
    name = s.abstract_type !== nothing ? :($(name) <: $(s.abstract_type)) : name
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
#| id: test-toplevel
module ComposeTest1
using ModuleMixins

@compose module A
    struct S
        a::Int
    end
end

@compose module B
    struct S{T}
        b::T
    end
end

@compose module AB
    @mixin A, B
end
end
```

```julia
#| id: test
@testset "compose struct members" begin
    @test ComposeTest1.AB.PARENTS == [:A, :B]
    @test fieldnames(ComposeTest1.AB.S) == (:a, :b)
end
@testset "compose hierarchy" begin
    @test ComposeTest1.AB.MIXIN_TREE == IdDict(:AB => [:A, :B], :A => [], :B => [])
    @test WriterABC.MIXIN_TREE == IdDict(
        :WriterABC => [:WriterB, :WriterC],
        :WriterC => [],
        :WriterB => [:WriterA],
        :WriterA => [])
end
@testset "composed struct has type parameter" begin
    @test ComposeTest1.AB.S{Float64}(1, 2).b isa Float64
end
```

```julia
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
    name::Symbol
end

function pass(p::CollectStructPass, expr)
    s = parse_struct(expr)
    s === nothing && return :nomatch
    mangle_type_parameters!(s, p.name)
    if s.name in keys(p.items)
        extend_struct!(p.items[s.name], s)
    else
        p.items[s.name] = s
    end
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

    function mixin(expr; name=name)
        structs = CollectStructPass(struct_items, name)
        parents = MixinPass([])
        pass1 = walk(parents, expr)
        mixin_tree[name] = parents.items
        for p in parents.items
            p in mixins && continue
            push!(mixins, p)
            parent_expr = Core.eval(__module__, :($(p).AST))
            mixin(parent_expr; name=p)
        end
        walk(usings + consts + structs, pass1)
    end

    fields = CollectStructPass(IdDict())
    walk(fields, body)

    clean_body = mixin(body)

    esc(Expr(:toplevel, :(module $name
        const AST = $body
        const PARENTS = [$(QuoteNode.(mixins)...)]
        const MIXIN_TREE = $(mixin_tree)
        const FIELDS = $(IdDict((n => v.fields for (n, v) in pairs(fields.items))...))
        $(usings.items...)
        $(consts.items...)
        $(define_struct.(values(struct_items))...)
        $(clean_body...)
    end)))
end
```

## For-each

The `@for_each` macro is meant for situations where you want to call a certain member function for each module that has it defined. Our use case: we have several components that need to write different bits of information to an output file. Each component defines a `write(io, data)` method. In our composed model, we can now call:

```julia
@for_each(P->P.write(io, data), PARENTS)
```

```julia
#| id: test-toplevel
module Common
    export AbstractData
    abstract type AbstractData end
end

@compose module WriterA
    using ..Common

    @kwdef struct Data <: AbstractData
        a::Int
    end

    function write(io::IO, data::AbstractData)
        println(io, data.a)
    end
end

@compose module WriterB
    using ..Common
    @mixin WriterA

    @kwdef struct Data <: AbstractData
        b::Int
    end

    function write(io::IO, data::AbstractData)
        println(io, data.b)
    end
end

@compose module WriterC
end

@compose module WriterABC
    using ModuleMixins
    @mixin WriterB, WriterC

    function write(io::IO, data::AbstractData)
        @for_each(P->P.write(io, data), PARENTS)
    end
end
```

```julia
#| id: test
@testset "for-each" begin
    io = IOBuffer(write=true)
    data = WriterABC.Data(a = 42, b = 23)
    WriterABC.write(io, data)
    @test String(take!(io)) == "23\n42\n"
end
```

```julia
#| id: for-each
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
```
