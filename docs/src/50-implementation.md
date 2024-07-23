```julia file=src/ModuleMixins.jl
module ModuleMixins



end
```

## `@spec`

The `@spec` macro stores a spec syntax in a newly created module.

``` {.julia #dsl-spec-defs}
@spec MySpec begin
    const msg = "hello"
end
```

``` {.julia #dsl-spec}
@test clean(MySpec.AST) == clean(:(begin const msg = "hello" end))
@test MySpec.msg == "hello"
```

The `@spec` macro is used to specify the structs of a model component.

``` {.julia #dsl}
"""
    @spec name body

Create a spec. When a spec is composed, the items in the spec will be spliced into a newly generated module. The `@spec` macro itself doesn't perform any operations other than storing the spec in a `const` expression. The real magic happens inside the `@compose` macro.
"""
macro spec(name, body)
    quoted_body = QuoteNode(body)

    clean_body = postwalk(e -> @capture(e, @requires parents__) ? :() : e, body)
    esc(Expr(:toplevel, :(module $name
        $(clean_body.args...)
        const AST = $quoted_body
    end)))
end

macro requires(deps...)
    esc(:(const PARENTS = [$(deps)...]))
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
