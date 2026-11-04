# Composition by closure

!!! note "Origin"
    This chapter, including the prototype code in `src/Components/Procedural.jl` and `examples/composition`, was written by Claude Opus 5.5 (Anthropic) at the request of Johan Hidding, on 2026-11-03 and 2026-11-04.

This page is a stand-alone prototype of the design discussed in [issue #14](https://github.com/jhidding/ModuleMixins.jl/issues/14). It doesn't use `@compose` at all. The question it tries to answer: can we keep what `@compose` is good at (diamond inheritance and automatically including all transitive dependencies), while composing values out of parts that Julia can dispatch on, instead of merging structs by name?

The prototype has three ingredients:

1. A **component** is an ordinary type (here, each component module defines an `Input` struct). A component declares what it depends on by extending `requires`. A dependency is either another component (a concrete type) or a **role** (an abstract type). A component fills a role by subtyping it, or by declaring it with `implements`, which lets one component fill several roles.
2. A **closure** computation walks those declarations, resolves roles, and returns every needed component exactly once, dependencies first. This is the part of `@compose` that handles the diamond.
3. A **`Composite`** holds one part per component. Property access is forwarded to the part that owns the field, so code can keep writing `input.t_step`, but each part keeps its own type for dispatch.

No macros are needed: the closure is computed by an ordinary function, and the composed type is just a `Composite` of a tuple of component types.

## Implementation

The library is the module `ModuleMixins.Procedural`.

!!! details "src/Components/Procedural.jl"

    ```julia
    #| file: src/Components/Procedural.jl
    module Procedural

    export requires, implements, default_implementation, closure, model_type,
        Composite, parts, component, map_components

    <<composition-requires>>
    <<composition-closure>>
    <<composition-composite>>
    <<composition-component>>
    <<composition-construct>>

    end
    ```

### Requirements and roles

By default a component has no dependencies. Components with dependencies extend `requires`. A role may name a default implementation, used when nothing else fills it.

Which roles a component fills is a trait: `implements(C, R)`. By default a component fills the roles it subtypes. A Julia struct has only one supertype, and it has to be chosen where the struct is defined. Extending `implements` lifts both restrictions: a component can fill any number of roles, and the declaration can be made anywhere, for example to adapt a component from another package. Roles are still abstract types. They only serve as names, so nothing needs to subtype them.

```julia
#| id: composition-requires
"""
    requires(T::Type)

The components (concrete types) or roles (abstract types) that component `T`
depends on. Extend this for every component that has dependencies.
"""
requires(::Type) = ()

"""
    implements(C::Type, R::Type)

Whether component `C` fills role `R`. Defaults to `C <: R`. Extend this to
let a component fill more than one role, or to declare a role for a
component defined elsewhere.
"""
implements(C::Type, R::Type) = C <: R

"""
    default_implementation(R::Type)

The component used to fill role `R` if no component implementing `R` is
selected explicitly.
"""
default_implementation(R::Type) =
    error("no component implementing role $(R) was selected, and there is no default")
```

### Closure

`closure` does a depth-first walk from the selected components, appending each component after its dependencies, so that every component appears once. Roles are resolved first: a component selected explicitly takes precedence over the default implementation. Selecting two implementations of the same role is an error, and so is a cycle.

```julia
#| id: composition-closure
"""
    resolve(R::Type, roots)

The component that fills requirement `R`. A concrete type is a component and
resolves to itself. A role resolves to the one component in `roots` that
implements it, or else to its `default_implementation`.
"""
function resolve(R::Type, roots)
    isabstracttype(R) || return R
    candidates = [C for C in roots if implements(C, R)]
    length(candidates) > 1 &&
        error("role $(R) is implemented by more than one component: $(candidates)")
    isempty(candidates) || return only(candidates)
    return default_implementation(R)
end

"""
    closure(roots::Type...)

Compute all components needed by `roots`, in dependency order (dependencies
first), each component appearing once. Abstract requirements (roles) are
resolved to a component implementing them: one of the `roots` if any, otherwise
`default_implementation`.
"""
function closure(roots::Type...)
    order = Type[]
    visiting = Type[]

    function visit(T)
        C = resolve(T, roots)
        C in order && return
        C in visiting && error("cyclic requirement: $(join([visiting; C], " -> "))")
        push!(visiting, C)
        foreach(visit, requires(C))
        pop!(visiting)
        push!(order, C)
    end

    foreach(visit, roots)
    return Tuple(order)
end
```

### Composite values

A `Composite` wraps a tuple of parts. Property access is forwarded to the part that has a field of that name. The lookup is done in a generated function, so for a constant property name it resolves at compile time and `input.t_step` is as fast as a field access.

The second type parameter records which part fills each role that a component in the model requires. It is a tuple of `RoleMap{R, i}` markers, meaning "role `R` is filled by part `i`". This is needed because role lookup also has to happen at compile time, but the generator of a `@generated` function may not call `implements`: methods added after the generator is defined, like the `implements` declarations of components, aren't reliably visible to it. So roles are resolved by `model_type`, which runs as ordinary code, and the generator only reads the result from the type. A composite built directly from parts, like the state composites below, has no roles.

```julia
#| id: composition-composite
"""
    RoleMap{R, i}

Marker type: role `R` is filled by part `i` of a composite.
"""
struct RoleMap{R, i} end

"""
    Composite{T <: Tuple, R <: Tuple}

A value composed of parts, one per component. Properties are forwarded to the
part that has a field of that name, so `c.x` works for any field `x` of any
part. `R` is a tuple of `RoleMap` markers, recording which part fills each role.
"""
struct Composite{T <: Tuple, R <: Tuple}
    parts::T
end

Composite(parts::Tuple) = Composite{typeof(parts), Tuple{}}(parts)

parts(c::Composite) = getfield(c, :parts)

# Index of the part that owns field `name`. Computed at compile time.
@generated function _owner(::Type{T}, ::Val{name}) where {T <: Tuple, name}
    i = findfirst(P -> hasfield(P, name), fieldtypes(T))
    i === nothing ? :(error("no component has a field `$(name)`")) : i
end

Base.getproperty(c::Composite, name::Symbol) =
    getfield(parts(c)[_owner(typeof(parts(c)), Val(name))], name)

Base.setproperty!(c::Composite, name::Symbol, value) =
    setproperty!(parts(c)[_owner(typeof(parts(c)), Val(name))], name, value)

Base.propertynames(c::Composite) = Tuple(Iterators.flatten(fieldnames.(typeof.(parts(c)))))

function Base.show(io::IO, c::Composite)
    print(io, "Composite(")
    join(io, parts(c), ", ")
    print(io, ")")
end
```

A component reaches its dependencies through `component`, which looks up a part by its type or by the role it implements. This is where dispatch comes in: the part that comes back has its own concrete type.

The lookup tries the role map first, then subtyping. Both are resolved at compile time. Only a role that no component in the model requires, and that isn't filled by subtyping, falls back to calling `implements` at run time. That still gives the right part, but it isn't type-stable.

```julia
#| id: composition-component
# Index of the part that is (or implements) `T`. Computed at compile time,
# except for roles that are neither in the role map nor filled by subtyping.
@generated function _index(::Type{P}, ::Type{R}, ::Type{T}) where {P <: Tuple, R <: Tuple, T}
    for m in fieldtypes(R)
        m.parameters[1] === T && return m.parameters[2]
    end
    i = findfirst(X -> X <: T, fieldtypes(P))
    i === nothing ? :(_index_dynamic(P, T)) : i
end

function _index_dynamic(::Type{P}, ::Type{T}) where {P <: Tuple, T}
    i = findfirst(X -> implements(X, T), fieldtypes(P))
    i === nothing && error("no component of type, or implementing, $(T)")
    return i
end

"""
    component(c::Composite, T)

The part of `c` that is of type `T`, or that implements role `T`.
"""
component(c::Composite{P, R}, ::Type{T}) where {P, R, T} = parts(c)[_index(P, R, T)]

"""
    map_components(f, c::Composite)

Apply `f` to every part of `c` and compose the results that aren't `nothing`.
"""
map_components(f, c::Composite) = Composite(Tuple(filter(!isnothing, map(f, parts(c)))))
```

### Construction

Users shouldn't need to know how a model is split into parts, so a composite is constructed from flat keyword arguments. Each argument is routed to the part that has a field of that name, and unknown arguments are an error. `model_type` computes the closure and checks that no field name is defined by two components, since forwarding would be ambiguous otherwise. It also resolves every role that a component in the model requires, and stores the result in the role map.

```julia
#| id: composition-construct
"""
    Composite{T, R}(; kwargs...)

Construct a composite from flat keyword arguments. Each keyword goes to the
part that has a field of that name.
"""
function (::Type{Composite{T, R}})(; kwargs...) where {T <: Tuple, R <: Tuple}
    types = fieldtypes(T)
    known = Set(Iterators.flatten(fieldnames.(types)))
    unknown = setdiff(keys(kwargs), known)
    isempty(unknown) || error("unknown arguments: $(join(unknown, ", "))")
    return Composite{T, R}(map(types) do P
        P(; (k => v for (k, v) in kwargs if hasfield(P, k))...)
    end)
end

"""
    model_type(roots::Type...)

The `Composite` type for the closure of `roots`.
"""
function model_type(roots::Type...)
    components = closure(roots...)
    names = collect(Iterators.flatten(fieldnames.(components)))
    duplicate = [n for n in unique(names) if count(==(n), names) > 1]
    isempty(duplicate) || error("field names defined by more than one component: $(duplicate)")

    roles = unique(R for C in components for R in requires(C) if isabstracttype(R))
    rolemap = (RoleMap{R, findfirst(==(resolve(R, roots)), components)} for R in roles)
    return Composite{Tuple{components...}, Tuple{rolemap...}}
end
```

### Tests

The tests use a role `A` that `X` fills by subtyping, a role `B` that `X` fills by trait, and a component `Y` that requires both.

```julia
#| file: test/ProceduralSpec.jl
module ProceduralSpec
using Test
using ModuleMixins.Procedural
import ModuleMixins.Procedural: requires, implements, default_implementation

abstract type A end
abstract type B end
abstract type C end

@kwdef struct X <: A
    x::Int = 1
end
@kwdef struct Y
    y::Int = 2
end
@kwdef struct Z <: A
    z::Int = 3
end

requires(::Type{Y}) = (A, B)
implements(::Type{X}, ::Type{B}) = true
implements(::Type{X}, ::Type{C}) = true
default_implementation(::Type{A}) = Z

@testset "Procedural" begin
    @test implements(X, A)
    @test implements(X, B)
    @test !implements(Z, B)

    @test closure(Y, X) == (X, Y)
    @test_throws ErrorException closure(Y)  # no default for B
    @test_throws ErrorException closure(Y, X, Z)  # A filled twice

    M = model_type(Y, X)
    m = M(x = 10)
    @test m.x == 10 && m.y == 2
    @test component(m, A) === component(m, B) === component(m, X)
    @test (@inferred component(m, B)) isa X

    # C is not required by any component, so it is found at run time
    @test component(m, C) isa X

    @test_throws ErrorException M(w = 1)
    @test_throws ErrorException component(m, Z)
end
end
```

## An elemental example

A small diamond: `Double` and `Square` both depend on a source of a value, and `Sum` depends on both. The source is a role, `AbstractSource`, with two implementations, `Constant` (the default) and `Ramp`. Every component has a `value` method that dispatches on its own type.

```mermaid
flowchart TD
    Sum --> Double --> Source[AbstractSource]
    Sum --> Square --> Source
    Constant -. implements .-> Source
    Ramp -. implements .-> Source
```

```julia
#| file: examples/composition/elemental.jl
using ModuleMixins.Procedural
import ModuleMixins.Procedural: requires, implements, default_implementation
using Test

<<elemental-components>>
<<elemental-run>>
```

The role is an abstract type, and `value` is the function every component implements.

```julia
#| id: elemental-components
abstract type AbstractSource end
function value end

module Constant
    import ..AbstractSource, ..value
    @kwdef struct Input <: AbstractSource
        c::Float64 = 1.0
    end
    value(s::Input, model) = s.c
end

module Ramp
    import ..AbstractSource, ..value
    @kwdef struct Input <: AbstractSource
        slope::Float64 = 1.0
        x::Float64 = 0.0
    end
    value(s::Input, model) = s.slope * s.x
end

default_implementation(::Type{AbstractSource}) = Constant.Input
```

`Double` and `Square` require the role, not a specific implementation, and find it with `component`.

```julia
#| id: elemental-components
module Double
    import ..AbstractSource, ..value, ..requires
    using ModuleMixins.Procedural: component
    @kwdef struct Input
        factor::Float64 = 2.0
    end
    requires(::Type{Input}) = (AbstractSource,)
    value(d::Input, model) = d.factor * value(component(model, AbstractSource), model)
end

module Square
    import ..AbstractSource, ..value, ..requires
    using ModuleMixins.Procedural: component
    struct Input end
    requires(::Type{Input}) = (AbstractSource,)
    value(::Input, model) = value(component(model, AbstractSource), model)^2
end

module Sum
    import ..value, ..requires
    using ModuleMixins.Procedural: component
    import ..Double, ..Square
    struct Input end
    requires(::Type{Input}) = (Double.Input, Square.Input)
    value(::Input, model) =
        value(component(model, Double.Input), model) +
        value(component(model, Square.Input), model)
end
```

Selecting only `Sum` is enough: the closure includes the source once, even though two components require it.

```julia
#| id: elemental-run
@show closure(Sum.Input)

const Model = model_type(Sum.Input)
m = Model(c = 3.0, factor = 10.0)
@show m
@show m.c m.factor
@show value(component(m, Sum.Input), m)
```

```
closure(Sum.Input) = (Main.Constant.Input, Main.Double.Input, Main.Square.Input, Main.Sum.Input)
m = Composite(Main.Constant.Input(3.0), Main.Double.Input(10.0), Main.Square.Input(), Main.Sum.Input())
m.c = 3.0
m.factor = 10.0
value(component(m, Sum.Input), m) = 39.0
```

To substitute the source, select `Ramp` explicitly. Both branches of the diamond now share the `Ramp`: $2 \cdot 3 + 3^2 = 15$.

```julia
#| id: elemental-run
const RampModel = model_type(Sum.Input, Ramp.Input)
@show closure(Sum.Input, Ramp.Input)
r = RampModel(slope = 2.0, x = 1.5)
@show value(component(r, Sum.Input), r)
```

```
closure(Sum.Input, Ramp.Input) = (Main.Ramp.Input, Main.Double.Input, Main.Square.Input, Main.Sum.Input)
value(component(r, Sum.Input), r) = 15.0
```

Property access and the whole `value` computation are type-stable. Mistakes are caught when the model is built: an unknown argument, or two components filling the same role.

```julia
#| id: elemental-run
get_c(m) = m.c
get_slope(m) = m.slope
@inferred get_c(m)
@inferred get_slope(r)
@inferred value(component(r, Sum.Input), r)

@test_throws ErrorException Model(colour = :red)
@test_throws ErrorException model_type(Sum.Input, Ramp.Input, Constant.Input)
```

### One component, two roles

A ramp also has a gradient. Suppose there is a second role, `AbstractGradient`, and a component `Slope` that reports the gradient of whatever fills that role. `Ramp` already subtypes `AbstractSource`, so it can't subtype `AbstractGradient` as well. Instead, the role is declared with `implements`. The declaration is made outside the `Ramp` module, as it would be if `Ramp` came from another package.

```julia
#| id: elemental-run
abstract type AbstractGradient end
function gradient end

gradient(s::Ramp.Input, model) = s.slope
implements(::Type{Ramp.Input}, ::Type{AbstractGradient}) = true

module Slope
    import ..AbstractGradient, ..value, ..gradient, ..requires
    using ModuleMixins.Procedural: component
    struct Input end
    requires(::Type{Input}) = (AbstractGradient,)
    value(::Input, model) = gradient(component(model, AbstractGradient), model)
end
```

Selecting `Ramp` once fills both roles, so `Sum` and `Slope` read from the same part. `AbstractGradient` has no default implementation, so a model that needs a gradient without selecting `Ramp` is an error.

```julia
#| id: elemental-run
const BothModel = model_type(Sum.Input, Slope.Input, Ramp.Input)
@show closure(Sum.Input, Slope.Input, Ramp.Input)
b = BothModel(slope = 2.0, x = 1.5)
@show value(component(b, Sum.Input), b)
@show value(component(b, Slope.Input), b)
@test component(b, AbstractSource) === component(b, AbstractGradient)

@inferred value(component(b, Slope.Input), b)
@test_throws ErrorException model_type(Sum.Input, Slope.Input)
println("all checks passed")
```

```
closure(Sum.Input, Slope.Input, Ramp.Input) = (Main.Ramp.Input, Main.Double.Input, Main.Square.Input, Main.Sum.Input, Main.Slope.Input)
value(component(b, Sum.Input), b) = 15.0
value(component(b, Slope.Input), b) = 2.0
all checks passed
```

## Porting the spring example

Here is the [spring example](@ref "Example") on top of `Procedural`. The structure stays the same: a `Time` component, a `Spring` component that depends on it, and a model. The differences:

- `Spring` declares its dependency with `requires` instead of `@mixin`.
- `initial_state` and `step!` are generic functions that dispatch on the component (the first argument). The composite versions loop over the parts in dependency order, which replaces `@constructor` and the hand-written `Model.step!`.
- The model is a single line, `model_type(Spring.Input)`.

```julia
#| file: examples/composition/spring.jl
using ModuleMixins.Procedural
import ModuleMixins.Procedural: requires
using Unitful
using CairoMakie

<<spring-common>>
<<spring-time>>
<<spring-spring>>
<<spring-damping>>
<<spring-run>>
```

The common module defines the two generic functions, with a no-op default for components that have no state or don't step.

```julia
#| id: spring-common
module Common
    using ModuleMixins.Procedural: Composite, parts, map_components

    """
        initial_state(part, input)

    The initial state of a single component, or `nothing` if it has no state.
    """
    initial_state(part, input) = nothing
    initial_state(input::Composite) = map_components(p -> initial_state(p, input), input)

    """
        step!(part, input, state)

    Advance the state of a single component. Components step in dependency order.
    """
    step!(part, input, state) = nothing
    step!(input::Composite, state) = foreach(p -> step!(p, input, state), parts(input))

    export initial_state, step!
end
```

Each component now has its own `Input` and `State` types. Methods take the component's own part as first argument for dispatch, and the full composite `input` and `state` to reach other components' fields.

```julia
#| id: spring-time
module Time
    using Unitful
    import ..Common: initial_state, step!

    @kwdef struct Input
        t_step::typeof(1.0u"s")
        t_end::typeof(1.0u"s")
    end

    mutable struct State
        time::typeof(1.0u"s")
    end

    initial_state(::Input, input) = State(0.0u"s")
    step!(::Input, input, state) = (state.time += input.t_step)

    function run(input)
        s = initial_state(input)
        Channel() do ch
            while s.time < input.t_end
                step!(input, s)
                put!(ch, deepcopy(s))
            end
        end
    end
end
```

```julia
#| id: spring-spring
module Spring
    using Unitful
    import ..Common: initial_state, step!
    import ..requires
    import ..Time

    @kwdef struct Input
        spring_constant::typeof(1.0u"s^-2")
        initial_position::typeof(1.0u"m")
    end

    mutable struct State
        position::typeof(1.0u"m")
        velocity::typeof(1.0u"m/s")
    end

    requires(::Type{Input}) = (Time.Input,)

    initial_state(::Input, input) = State(input.initial_position, 0.0u"m/s")

    function step!(::Input, input, state)
        delta_v = -input.spring_constant * state.position
        state.position += state.velocity * input.t_step
        state.velocity += delta_v * input.t_step
    end
end
```

The original `Model.step!` stepped the spring before the time. Here the time steps first, because it is a dependency. The spring doesn't read the time, so the result is the same: running both versions gives identical positions.

### Extending from outside

A new component doesn't need anything from the namespaces of the components it builds on, other than the names it uses. `Damping` is written as if it lived in a separate package, referring to everything by absolute path. Selecting `Damping` pulls in `Spring`, and through it `Time`.

```julia
#| id: spring-damping
module Damping
    using Unitful
    import ModuleMixins.Procedural: requires
    import Main.Common: step!
    import Main.Spring

    @kwdef struct Input
        damping::typeof(1.0u"s^-1")
    end

    requires(::Type{Input}) = (Spring.Input,)

    step!(::Input, input, state) =
        (state.velocity -= input.damping * state.velocity * input.t_step)
end
```

```julia
#| id: spring-run
const Model = model_type(Spring.Input)
const DampedModel = model_type(Damping.Input)
@show closure(Damping.Input)

parameters = (
    t_step = 0.001u"s",
    t_end = 1.0u"s",
    spring_constant = 250.0u"s^-2",
    initial_position = 1.0u"m",
)

function plot_result()
    output = Time.run(Model(; parameters...)) |> collect
    damped = Time.run(DampedModel(; parameters..., damping = 3.0u"s^-1")) |> collect

    fig = Figure()
    ax = Axis(fig[1, 1]; xlabel = "time [s]", ylabel = "position [m]")
    for (label, run) in ["spring" => output, "damped spring" => damped]
        lines!(ax, [s.time for s in run] ./ u"s", [s.position for s in run] ./ u"m";
               label = label)
    end
    axislegend(ax)
    save("docs/src/fig/composition-spring.svg", fig)
end

plot_result()
```

```
closure(Damping.Input) = (Main.Time.Input, Main.Spring.Input, Main.Damping.Input)
```

![Spring, with and without damping](fig/composition-spring.svg)

## Compared to `@compose`

What stays the same:

- **Diamonds and transitive closure.** A model names only the components it needs directly, and shared dependencies appear once.
- **A flat user interface.** Models are still constructed with flat keyword arguments, and code still reads `input.t_step`.

What changes:

- **Components are types, not modules.** Each part keeps its own type, so behaviour is selected by dispatch instead of `@for_each` over module names.
- **Substitution through roles.** A component can depend on a role, and any component implementing it fills the role for every dependant at once (see #4).
- **No code generation from stored syntax.** There is no `Core.eval` of parent ASTs, and no copied `using` statements, so components can be defined anywhere (see #16).
- **Ordinary Julia tooling applies.** Struct definitions are written out where they are defined, so they can be found, documented and revised like any other struct.

Limitations shared with `@compose`:

- **Field names must be unique across a model.** Forwarding needs to know which part owns a name, just as `@compose` needs it to merge fields. `model_type` checks this.
- **Dependency order is the only order.** `step!` runs components in dependency order. A model that needs a different order defines its own `step!`, as `@compose` models do now.

Both depend on which components end up in the model, so they can only be checked or resolved when the model is assembled.

Limitation of this prototype:

- **No per-item records.** In CarboKitten, components contribute fields not only to the top-level input but also to each facies (`Production`, `CellularAutomaton`, `Denudation` and others each define a `Facies` struct), and `@compose` merges those as well. The prototype composes a single record per model. This is the only real regression.

## Lifting the limitations

### Roles as traits

An earlier version of this prototype used subtyping as the only way to fill a role. Since a Julia struct has one supertype, chosen where the struct is defined, a component could fill only one role. Role membership is now the trait `implements(C, R)` (see [Requirements and roles](@ref)), which defaults to subtyping and can be extended anywhere. The example [One component, two roles](@ref) shows it in use. Two consequences of this design:

- `implements` is user-extensible, so it can't be called from the generator of a `@generated` function. Roles are therefore resolved in `model_type` and stored in the composite type as a role map. A role that no component in the model requires is still found by `component`, but at run time.
- Methods can't dispatch on a role that is filled by trait (`value(s::AbstractSource, model)` only matches subtypes). Where that's needed, the usual Holy-trait pattern applies. In practice components find each other through `component(model, Role)`, which works either way.

### A local, module-level macro

A macro similar to `@compose` can make these extensions comfortable to use. The difference from `@compose` is that its syntax transformation is purely local: it reads only the module it's applied to and expands into ordinary method definitions (`requires`, `implements`, ...). It never inspects or re-evaluates code from parent modules. The function protocol stays the specification, and the macro is optional shorthand: a component written by hand, like `Damping` above, keeps working.

```julia
@component module Ramp
    @implements AbstractSource AbstractClock
    @kwdef struct Input
        slope::Float64 = 1.0
        x::Float64 = 0.0
    end
end

@component module Spring
    @mixin Time         # requires(::Type{Input}) = (Time.Input,)
    ...
end
```

The macro can also catch mistakes when a component is defined, such as a module without an `Input`, or a `@mixin` that names something that isn't a component.

Per-item records are where the macro does more than save typing. The component that owns the collection needs a field whose element type is the composite of every component's `Facies` part. That type is only known once the model is assembled, so the struct has to be parametric. The macro can do this rewrite so users don't see the type parameter:

```julia
# written in FaciesBase
@kwdef struct Input
    facies::Vector{Facies} = []
end

# emitted by the macro
@kwdef struct Input{F}
    facies::Vector{F} = []
end
item_collection(::Type{<:Input}) = (:facies,)
```

In every other component that defines a `struct Facies`, the macro emits something like `item_part(::Type{Input}, ::Val{:facies}) = Facies`. `model_type` collects these parts in closure order, builds `Composite{Tuple{FaciesBase.Facies, Production.Facies, ...}}`, and substitutes it for `F`. Each `input.facies[i]` is then a composite, with flat property access and per-component dispatch, like the top-level input. Still open: constructing per-item composites from the flat per-facies arguments users pass now, and components that have no per-item part.

With roles as traits and per-item records covered by the macro, the composition approach would do everything `@compose` does. Its remaining limitations would be the ones `@compose` already has.
