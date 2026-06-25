# Etudes in Macro Programming

The way `ModuleMixins` is implemented, is that we start out with something relatively simple, and build out from that. This means there will be some redudant code. Macros are hard to engineer, this takes you through the entire process.

Before we explain the full `@compose` macro, we can do some finger exercises to understand the mechanisms behind its implementation.

## `@spec`

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

## `@spec_mixin`

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

## Module Templates

How cool it would be, if we can parametrise a module. Julia rules that modules can only be defined at top-level. So we have to go by the macro route once more. First, we try to implement the desired effect in isolation.

Every module template will have a name, body and a list of parameters.
Each parameter may have a default argument specified, similar to how functions in Julia can have defaults.

### Spec

```julia
#| file: test/TemplatesSpec.jl
using ModuleMixins.Templates: @lambda, @instantiate, ModuleTemplate

@lambda module TempA{T}
    struct S
        x::T
    end
end

@lambda module TempB{M}
    const X = M.X
end

module M1
    const X = 42
end

@testset "ModuleMixins.Templates" begin
    @test TempA isa ModuleTemplate
    @instantiate TempAi = TempA{Int}

    @test TempAi.T === Int
    @test TempAi.S(4).x isa Int

    @instantiate TempAf = TempA{Float64}

    @test TempAf.T === Float64
    @test TempAf.S(4).x isa Float64

    @instantiate TempBM1 = TempB{M1}
    @test TempBM1.X == 42
end
```

### Implementation

```julia
#| id: template-parameter
struct Parameter
    name::Symbol
    default::Union{Some{Any}, Nothing}
end

name(parameter) = parameter.name
has_default(parameter) = parameter.default !== nothing
default(parameter) = something(parameter.default)

function make_parameter(expr)
    if @capture(expr, name_ = default_)
        return Parameter(name, Some(default))
    elseif expr isa Symbol
        return Parameter(expr, nothing)
    else
        error("Unknown parameter syntax `$(expr)`.")
    end
end
```

When arguments are passed to the template instantiation, they are either given positional (i.e. value only) or keyword style (`key = value`). When we convert a given syntax into an argument, we need to evaluate the value in the calling context.

```julia
#| id: template-argument
struct Argument
    name::Union{Symbol, Nothing}
    value::Any
end

positional(argument) = argument.name === nothing

eval_argument(mod) = function (expr)
    value = if @capture(expr, name_ = value_)
        value
    else
        expr
    end
    return Argument(name, @eval(mod, $(value)))
end
```

Given a list of parameters and a list of arguments, we can create a list of bound variables. Here we lay down some rules:

- positional arguments can never follow a keyword argument.
- at the end of the binding process, we obtain a `name` / `value` pair for each parameter, in the same order as the parameters were defined.

A bound variable will result in the injection of a `const` definition.

```julia
#| id: template-bound-variable
struct BoundVariable
    name::Symbol
    value::Any
end

function bind(pars, args)
    positional_args = Iterators.takewhile(positional, args) |> collect
    keyword_args = Dict(arg.name => arg for arg in args[length(positional_args)+1:end])
    keyword_pars = pars[length(positional_args)+1:end]
    @assert(!any(positional, values(keyword_args)))
    positional_bindings = (BoundVariable(par.name, arg.value)
        for (par, arg) in Iterators.zip(pars, positional_args))
    keyword_bindings = (BoundVariable(par.name, par.name in keys(keyword_args) ?
        keyword_args[par.name].value :
        par.default) for par in keyword_pars)
    bindings = Iterators.flatten(
        (positional_bindings, keyword_bindings)) |> collect
    @assert(name.(pars) == name.(bindings))
    return bindings
end

function as_expression(bv::BoundVariable)
    return :(const $(bv.name) = $(bv.value))
end
```

We define a module with arguments using the `@lambda` macro, and create an instance with `@instantiate`.

```julia
#| file: src/Templates.jl
module Templates
    using MacroTools: @capture
    export @lambda, @instantiate

    <<template-parameter>>
    <<template-argument>>
    <<template-bound-variable>>

    struct ModuleTemplate
        name::Symbol
        environment::Module
        parameters::Vector{Parameter}
        body::Vector{Any}
    end

    macro lambda(expr)
        @assert @capture(expr, module name_ body__ end)
        if isempty(body) | !@capture(body[1], {raw_parameters__})
            return esc(Expr(:toplevel, :(module $name
                $(body...)
                const AST = $body
            end)))
        end
        parameters = raw_parameters .|> make_parameter |> filter(!isnothing) |> collect
        template = ModuleTemplate(name, __module__, parameters, body[2:end])
        return esc(Expr(:toplevel, :(const $name = $template)))
    end

    macro instantiate(expr)
        @assert @capture(expr, instance_name_ = template_name_{raw_arguments__})
        arguments = raw_arguments .|> eval_argument(__module__)
        template = @eval(__module__, $(template_name))
        bound_vars = bind(template.parameters, arguments)
        module_expr = Expr(:toplevel, :(module $(instance_name)
            $(as_expression.(bound_vars)...)
            $(template.body...)
        end))
        result = @eval(template.environment, $(module_expr))
        return :(using $(nameof(template.environment)).$(instance_name))
    end
end
```
