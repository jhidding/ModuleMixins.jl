# Implementation

The way `ModuleMixins` is implemented, is that we start out with something relatively simple, and build out from that. This means there will be some redudant code. Macros are hard to engineer, this takes you through the entire process.

## Prelude

```julia
#| file: src/ModuleMixins.jl
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

<<compose>>
<<for-each>>

end
```

To facilitate testing, we need to be able to compare syntax. We use the `clean` function to remove source information from expressions.

```julia
#| file: test/runtests.jl
using Test

@testset "ModuleMixins.jl" begin
    include("SpecSpec.jl")
    include("PassesSpec.jl")
    include("MixinsSpec.jl")
    include("StructsSpec.jl")
    include("ConstructorsSpec.jl")
    include("ComposeSpec.jl")
end
```

## Etudes in Macro Programming

### `@spec`

The `@spec` macro creates a new module, and stores its own AST inside that module.

!!! details "src/Spec.jl"

    ```julia
    #| file: src/Spec.jl
    module Spec

    using MacroTools: @capture
    export @spec

    <<spec>>

    end
    ```

We may test that this works using a small example.

!!! details "test/SpecSpec.jl"

    ```julia
    #| file: test/SpecSpec.jl
    <<test-spec-toplevel>>

    @testset "ModuleMixins.Spec" begin
        using MacroTools: prewalk, rmlines
        clean(expr) = prewalk(rmlines, expr)

        <<test-spec>>
    end
    ```

```julia
#| id: test-spec-toplevel
using ModuleMixins.Spec: @spec, @spec_mixin, @mixin

@spec module MySpec
const msg = "hello"
end
```

```julia
#| id: test-spec
@testset "@spec" begin
    @test clean.(MySpec.AST) == clean.([:(const msg = "hello")])
    @test MySpec.msg == "hello"
end
```

This may seem like a silly example, but storing the AST of a module inside itself is very powerful. It means that inside macros we can always return to original expressions of other modules and devise ways of combining, composing and compiling new modules from them.

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

Inside `ModuleMixins` we make extensive use of `MacroTools.@capture`. Preceding `@capture` with `@assert` is a quickfire way of making sure that our macro was called with the correct syntax.

When defining a new module we have to create a **top-level expression**, and call `esc` on the entire expression to make sure no symbols are mangled.

### `@spec_mixin`

We now add the `@mixin` syntax. This still doesn't do anything, other than storing the names of parent modules.

```julia
#| id: test-spec-toplevel
@spec_mixin module MyMixinSpecOne
@mixin A
end
@spec_mixin module MyMixinSpecMany
@mixin A, B, C
end
```

```julia
#| id: test-spec
@testset "@spec_mixin" begin
    @test MyMixinSpecOne.PARENTS == [:A]
    @test MyMixinSpecMany.PARENTS == [:A, :B, :C]
end
```

Here's the `@mixin` macro:

```julia
#| id: spec
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

## Passes

We now use the `prewalk` function (from `MacroTools.jl`) to transform expressions and collect information into searchable data structures. We make a little abstraction over the `prewalk` function, so we can compose multiple transformations in a single tree walk.

An implementation of the `pass` function should take a `Pass` object and an expression (or symbol), and return `no_match` if the expression did not match the pattern.

Types that derive from `Pass` can be added into a composite `CompositePass` using the `+` operator.

```julia
#| file: src/Passes.jl
module Passes

using MacroTools: prewalk

export Pass, pass, no_match, walk

abstract type Pass end

struct NoMatch end

const no_match = NoMatch()

"""
    pass(x::Pass, expr)

Interface. An implementation of the `pass` function should take a `Pass` object
and an expression (or symbol), and return `no_match` if the expression did not
match the pattern.

You can use the given `Pass` object to store information about this pass, return
syntax that should replace the current expression, or `nothing` if it should be
removed.
"""
function pass(x::Pass, expr)
    error("Can't call `pass` on abstract `Pass`.")
end

struct CompositePass <: Pass
    parts::Vector{Pass}
end

Base.:+(a::CompositePass...) = CompositePass(splat(vcat)(getfield.(a, :parts)))
Base.convert(::Type{CompositePass}, a::Pass) = CompositePass([a])
Base.:+(a::Pass...) = splat(+)(convert.(CompositePass, a))

"""
    pass(x::CompositePass, expr)

Tries all passes in a composite pass in order, and returns with the first
that succeeds (i.e. doesn't return `no_match`). You may create a `CompositePass`
by adding passes with the `+` operator.
"""
function pass(cp::CompositePass, expr)
    for p in cp.parts
        result = pass(p, expr)
        if result !== no_match
            return result
        end
    end
    return no_match
end

"""
    walk(x::Pass, expr_list)

Calls `MacroTools.prewalk` with the given `Pass`. If `no_match` is returned,
the expression stays untouched.
"""
function walk(x::Pass, expr_list)
    function patch(expr)
        result = pass(x, expr)
        result === no_match ? expr : result
    end
    prewalk.(patch, expr_list)
end

end
```

A composite pass tries all of its parts in order, returning the value of the first pass that doesn't return `no_match`.

### Tests

!!! details "test/PassesSpec.jl"

    ```julia
    #| file: test/PassesSpec.jl
    @testset "ModuleMixins.Passes" begin
        using ModuleMixins.Passes: Passes, Pass, no_match, pass, walk

        <<test-passes>>
    end
    ```

We define a small pass that replaces some symbol with `blip!`.

```julia
#| id: test-passes
struct BlipPass <: Pass
    tag::Symbol
end

Passes.pass(p::BlipPass, expr) = expr == p.tag ? :blip! : no_match
```

We can test that this works on small tuple expression.

```julia
#| id: test-passes
@testset "pass replacement" begin
    @test walk(BlipPass(:a), [:(a, b)])[1] == :(blip!, b)
    @test walk(BlipPass(:b), [:(a, b)])[1] == :(a, blip!)
end
```

And then that it composes to replace both elements in the tuple.

```julia
#| id: test-passes
@testset "pass composition" begin
    a = BlipPass(:a) + BlipPass(:b)
    @test walk(a, [:(a, b)])[1] == :(blip!, blip!)
end
```

## Mixin Pass
The `MixinPass` now filters for appearances of the `@mixin <Component>` syntax and transforms them into `using ..<Component>`. This assumes that the symbols used are visible in the parent module.

```julia
#| file: src/Mixins.jl
module Mixins

using MacroTools: @capture
import ..Passes: Pass, pass, no_match, walk

@kwdef struct MixinPass <: Pass
    items::Vector{Symbol}
end

function pass(m::MixinPass, expr)
    @capture(expr, @mixin deps_) || return no_match

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

end
```

### Test: `@spec_using`

I can't think of any usecase where a `@mixin A`, doesn't also mean `using ..A`. By replacing the `@mixin` with a `using` statement, we also no longer need to import `@mixin`. In fact, that macro becomes redundant. Also, in `@spec_using` we're allowed multiple `@mixin` statements.

```julia
#| file: test/MixinsSpec.jl
using ModuleMixins.Mixins: @spec_using

@testset "ModuleMixins.Mixins" begin
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

    @testset "@spec_using" begin
        @test SU_B.Y == SU_A.X
        @test SU_B.PARENTS == [:SU_A]
        @test SU_D.PARENTS == [:SU_A, :SU_B, :SU_C]
        @test SU_D.SU_C.Z == :goodbye
    end
end
```

## Structure of structs

We'll convert `struct` syntax into collectable data, then convert that back into structs again. We'll support several patterns:

!!! details "test/StructsSpec.jl"

    ```julia
    #| file: test/StructsSpec.jl
    @testset "ModuleMixins.Structs" begin
        using ModuleMixins.Structs: Struct, parse_struct, define_struct, mangle_type_parameters!
        using MacroTools: prewalk, rmlines
        clean(expr) = prewalk(rmlines, expr)

        <<test-structs>>
    end
    ```

```julia
#| id: test-structs
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
#| id: test-structs
@testset "Struct mangling abstracts" begin
    @test parse_struct(:(struct A <: B x end)).abstract_type == :B
    @test parse_struct(:(mutable struct A <: B x end)).abstract_type == :B
end

@testset "Mangling type arguments" begin
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

@testset "Getting fieldnames" begin
    let s = parse_struct(:(struct S x; y; z end))
        @test fieldnames(s) == [:x, :y, :z]
    end
end
```

### Implementation

!!! details "src/Structs.jl"

    ```julia
    #| file: src/Structs.jl
    module Structs

    using MacroTools: @capture, postwalk
    import ..Passes: Pass, pass, no_match

    <<struct-data>>
    <<collect-struct-pass>>

    end
    ```

We need to store all information on a struct definition, so that we can reconstruct
the original expression, or a similar expression with extended fields.

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
```

If we have a type parameter called `T`, we want to rename it so that it
can't clash with previously defined type parameters.

```julia
#| id: struct-data
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

function Base.fieldnames(s::Struct)
    get_fieldname(def::Symbol) = def
    function get_fieldname(def::Expr)
        if @capture(def, name_::type_)
            return name
        end
        if @capture(def, name_::type_ = default_)
            return name
        end
        error("unknown struct field expression: $(def)")
    end

    return get_fieldname.(s.fields)
end
```

### Collecting structs

```julia
#| id: collect-struct-pass
struct CollectStructPass <: Pass
    items::IdDict{Symbol,Struct}
    name::Symbol
end

function pass(p::CollectStructPass, expr)
    s = parse_struct(expr)
    if s === nothing
        return no_match
    end

    mangle_type_parameters!(s, p.name)
    if s.name in keys(p.items)
        extend_struct!(p.items[s.name], s)
    else
        p.items[s.name] = s
    end
    return nothing
end
```

## `@compose`

Unfortunately now comes a big leap. We'll merge all struct definitions inside the body of a module definition with that of its parents. We must also make sure that a `struct` definition still compiles, so we have to take along `using` and `const` statements.

!!! details "test/ComposeSpec.jl"

    ```julia
    #| file: test/ComposeSpec.jl
    using ModuleMixins

    <<test-compose-toplevel>>

    @testset "ModuleMixins.Compose" begin
        using ModuleMixins: @compose

        <<test-compose>>
    end
    ```

```julia
#| id: test-compose-toplevel
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
#| id: test-compose
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
```

## Constructors

```julia
#| file: src/Constructors.jl
module Constructors

using MacroTools: @capture
using .Iterators: repeated

import ..Passes: Pass, pass, no_match
import ..Structs: Struct

<<constructor-pass>>

end
```

Once we have several structs in place, we might want to generate one type from another. Suppose we have an `Input` struct and a `State` struct, and we want to automatically compose an `initial_state` function. We can do this if we have a function `state_field(input::Input)` returning the initial state for some field of `State`. We also may have the situation that we want to compute several fields in one go for efficiency.

```julia
@constructor function initial_state(input::Input)::State
    return (
        state_var1 = 42,
        ...
    )
end
```

```julia
#| file: test/ConstructorsSpec.jl
module ConstructorTest
    using ModuleMixins

    @compose module CtA
        struct S
            x
        end

        @constructor function make_s()::S
            (x = 5,)
        end
    end

    @compose module CtB
        @mixin CtA

        struct S
            y
            z
        end

        @constructor function make_s()::S
            (y = 7, z = 9)
        end
    end
end

@testset "ModuleMixins.Constructors" begin
    using .ConstructorTest: CtA, CtB
    using ModuleMixins

    @test CtA.make_s() == CtA.S(5)
    @test CtB.make_s() == CtB.S(5, 7, 9)
end
```

### Implementation

The following defines a macro that converts that syntax into usable information to compose a larger constructor.

```julia
#| id: constructor-pass
struct Constructor
    name::Symbol
    arg_names::Vector{Symbol}
    return_type_name::Symbol
    parts::Vector{Pair{Vector{Symbol}, Expr}}
end

function Base.:+(a::Constructor, b::Constructor)
    @assert a.name == b.name
    @assert a.arg_names == b.arg_names
    @assert a.return_type_name == b.return_type_name
    @assert isdisjoint(first.(a.parts), first(b.parts))

    return Constructor(
        a.name, a.arg_names, a.return_type_name,
        vcat(a.parts, b.parts))
end

Base.fieldnames(c::Constructor) = vcat(first.(c.parts)...)

named_tuple_keys(::Type{NamedTuple{names, types}}) where {names, types} = names
named_tuple_keys(::Type{NamedTuple{names, <:types}}) where {names, types} = names
arg_name(arg::Symbol) = arg
arg_name(expr::Expr) = begin
    @capture(expr, name_::atype_)
    name
end

function parse_constructor(f)
    @assert @capture(f, function name_(args__)::return_type_name_ body__ end)
    n_args = length(args)
    arg_names = [arg_name(a) for a in args]
    expr = :(function ($(arg_names...),) $(body...) end)

    rt_vec = Base.return_types(eval(expr), (repeated(Any, n_args)...,))
    @assert (length(rt_vec) == 1) "constructor function should be type stable"
    rt = rt_vec[1]
    @assert (rt <: NamedTuple) "constructor function should return a NamedTuple"
    ret_names = [named_tuple_keys(rt)...]

    return Constructor(name, arg_names, return_type_name, [ret_names => expr])
end
```

We can turn this into a `Pass`, so that the `@constructor` macro gets integrated into `@compose`.

```julia
#| id: constructor-pass
struct CollectConstructorPass <: Pass
    items::IdDict{Symbol, Constructor}
end

function pass(p::CollectConstructorPass, expr)
    @capture(expr, @constructor constructor_expr_) || return no_match
    data = parse_constructor(constructor_expr)

    key = data.return_type_name
    if key in keys(p.items)
        p.items[key] += data
    else
        p.items[key] = data
    end

    return nothing
end

function define_constructor(s::Struct, c::Constructor)
    @assert s.name == c.return_type_name
    @assert issetequal(fieldnames(s), fieldnames(c)) "constructor should construct all fields of struct, expected $(fieldnames(s)), got $(fieldnames(c))"
    return :(function $(c.name)($(c.arg_names...),)
        $((:(($(first(p)...),) = ($(last(p)))($(c.arg_names...),))
           for p in c.parts)...)
        $(c.return_type_name)($(fieldnames(s)...),)
    end)
end
```

## For-each

The `@for_each` macro is meant for situations where you want to call a certain member function for each module that has it defined. Our use case: we have several components that need to write different bits of information to an output file. Each component defines a `write(io, data)` method. In our composed model, we can now call:

```julia
@for_each(P->P.write(io, data), PARENTS)
```

```julia
#| id: test-compose-toplevel
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
#| id: test-compose
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
