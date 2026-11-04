# ~/~ begin <<docs/src/41-composition.md#src/Components/Procedural.jl>>[init]
module Procedural

export requires, implements, default_implementation, closure, model_type,
    Composite, parts, component, map_components

# ~/~ begin <<docs/src/41-composition.md#composition-requires>>[init]
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
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#composition-closure>>[init]
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
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#composition-construct>>[init]
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
# ~/~ end

end
# ~/~ end
