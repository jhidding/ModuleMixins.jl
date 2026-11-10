# ~/~ begin <<docs/src/41-composition.md#src/Components/Procedural.jl>>[init]
module Procedural

export requires, implements, default_implementation, closure,
    record_part, record_type, Composite, parts, component, map_components

# ~/~ begin <<docs/src/41-composition.md#composition-requires>>[init]
"""
    requires(::Val{M})

The components (modules) or roles (abstract types) that component `M`
depends on. Extend this for every component that has dependencies.
"""
requires(::Val) = ()
requires(M::Module) = requires(Val(M))

"""
    implements(::Val{M}, R::Type)

Whether component `M` fills role `R`. Defaults to `false`.
"""
implements(::Val, ::Type) = false
implements(M::Module, R::Type) = implements(Val(M), R)

"""
    default_implementation(R::Type)

The component (module) used to fill role `R` if no component implementing `R`
is selected explicitly.
"""
default_implementation(R::Type) =
    error("no component implementing role $(R) was selected, and there is no default")
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#composition-closure>>[init]
"""
    resolve(R, roots)

The component that fills requirement `R`. A module is a component and resolves
to itself. A role resolves to the one component in `roots` that implements it,
or else to its `default_implementation`.
"""
resolve(M::Module, roots) = M

function resolve(R::Type, roots)
    candidates = [M for M in roots if implements(M, R)]
    length(candidates) > 1 &&
        error("role $(R) is implemented by more than one component: $(candidates)")
    isempty(candidates) || return only(candidates)
    return default_implementation(R)
end

resolve(x, roots) = error("requirement $(x) is neither a component (module) nor a role (type)")

"""
    closure(roots::Module...)

Compute all components needed by `roots`, in dependency order (dependencies
first), each component appearing once. Roles are resolved to a component
implementing them: one of the `roots` if any, otherwise `default_implementation`.
"""
function closure(roots::Module...)
    order = Module[]
    visiting = Module[]

    function visit(R)
        M = resolve(R, roots)
        M in order && return
        M in visiting && error("cyclic requirement: $(join([visiting; M], " -> "))")
        push!(visiting, M)
        foreach(visit, requires(M))
        pop!(visiting)
        push!(order, M)
    end

    foreach(visit, roots)
    return Tuple(order)
end
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#composition-composite>>[init]
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
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#composition-component>>[init]
# Index of the part defined in module `M`. Computed at compile time.
@generated function _component_index(::Type{P}, ::Val{M}) where {P <: Tuple, M}
    i = findfirst(X -> parentmodule(X) === M, fieldtypes(P))
    i === nothing ? :(error("component $(M) has no part in this record")) : i
end

# Index of the part of type `T`, or that implements role `T`. Computed at
# compile time, except for roles that are not in the role map.
@generated function _type_index(::Type{P}, ::Type{R}, ::Type{T}) where {P <: Tuple, R <: Tuple, T}
    if isabstracttype(T)
        for m in fieldtypes(R)
            m.parameters[1] === T && return m.parameters[2]
        end
        return :(_role_index_dynamic(P, T))
    end
    i = findfirst(X -> X <: T, fieldtypes(P))
    i === nothing ? :(error("no part of type $(T) in this record")) : i
end

function _role_index_dynamic(::Type{P}, ::Type{T}) where {P <: Tuple, T}
    i = findfirst(X -> implements(parentmodule(X), T), fieldtypes(P))
    i === nothing && error("no part implementing role $(T)")
    return i
end

"""
    component(c::Composite, ::Val{M})
    component(c::Composite, M::Module)
    component(c::Composite, T::Type)

The part of `c` contributed by component `M`, the part of type `T`, or, if `T`
is a role (an abstract type), the part contributed by the component that
implements `T`. Pass a module as `Val(M)` for a type-stable lookup.
"""
component(c::Composite{P}, ::Val{M}) where {P, M} = parts(c)[_component_index(P, Val(M))]
component(c::Composite, M::Module) = component(c, Val(M))
component(c::Composite{P, R}, ::Type{T}) where {P, R, T} = parts(c)[_type_index(P, R, T)]

"""
    map_components(f, c::Composite)

Apply `f` to every part of `c` and compose the results that aren't `nothing`.
"""
map_components(f, c::Composite) = Composite(Tuple(filter(!isnothing, map(f, parts(c)))))
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#composition-records>>[init]
"""
    record_part(M::Module, name::Symbol)

The part that component `M` contributes to record `name`: the type `M.name`
if `M` defines it, otherwise `nothing`.
"""
function record_part(M::Module, name::Symbol)
    isdefined(M, name) || return nothing
    T = getfield(M, name)
    T isa Type && parentmodule(T) === M ? T : nothing
end

"""
    type_parameter_names(T)

The names of the type parameters of a `UnionAll` type, in order.
"""
function type_parameter_names(T)
    names = Symbol[]
    while T isa UnionAll
        push!(names, T.var.name)
        T = T.body
    end
    return names
end

function check_unique_fields(types)
    names = collect(Iterators.flatten(fieldnames.(types)))
    duplicate = [n for n in unique(names) if count(==(n), names) > 1]
    isempty(duplicate) || error("field names defined by more than one component: $(duplicate)")
end

"""
    record_type(name::Symbol, roots::Module...; parameters...)

The `Composite` type of record `name`, for the closure of `roots`. It has one
part for every component that defines a type `name`, in dependency order.

A type parameter of a part that is named after a record is filled with the
composite type of that record. Any other type parameter is taken from
`parameters`, by name.
"""
function record_type(name::Symbol, roots::Module...; parameters...)
    components = closure(roots...)
    roles = unique(R for M in components for R in requires(M) if R isa Type)
    resolved = [R => resolve(R, roots) for R in roles]
    return _record_type(name, components, resolved, NamedTuple(parameters), Symbol[])
end

is_record(name, components) = any(M -> record_part(M, name) !== nothing, components)

function _record_type(name, components, resolved, parameters, visiting)
    name in visiting && error("record $(name) contains itself: $(join([visiting; name], " -> "))")
    owners = [M for M in components if record_part(M, name) !== nothing]
    isempty(owners) && error("no component defines a record part `$(name)`")

    function parameter(P, n)
        record = is_record(n, components)
        given = haskey(parameters, n)
        record && given &&
            error("type parameter `$(n)` of $(P) names a record, and is also given as a keyword")
        record && return _record_type(n, components, resolved, parameters, visiting)
        given && return parameters[n]
        error("type parameter `$(n)` of $(P) is not a record, and is not given as a keyword to `record_type`")
    end

    push!(visiting, name)
    record_parts = map(owners) do M
        P = record_part(M, name)
        inner = type_parameter_names(P)
        isempty(inner) ? P : P{map(n -> parameter(P, n), inner)...}
    end
    pop!(visiting)

    check_unique_fields(record_parts)
    rolemap = [RoleMap{R, findfirst(==(M), owners)} for (R, M) in resolved if M in owners]
    return Composite{Tuple{record_parts...}, Tuple{rolemap...}}
end
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#composition-records>>[1]
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

Base.convert(::Type{C}, x::NamedTuple) where {C <: Composite} = C(; x...)
# ~/~ end

end
# ~/~ end
