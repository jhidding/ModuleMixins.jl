# ~/~ begin <<docs/src/41-composition.md#examples/composition/composition.jl>>[init]
module Composition

export requires, default_implementation, closure, model_type,
    Composite, parts, component, map_components

# ~/~ begin <<docs/src/41-composition.md#composition-requires>>[init]
"""
    requires(T::Type)

The components (concrete types) or roles (abstract types) that component `T`
depends on. Extend this for every component that has dependencies.
"""
requires(::Type) = ()

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
    closure(roots::Type...)

Compute all components needed by `roots`, in dependency order (dependencies
first), each component appearing once. Abstract requirements (roles) are
resolved to a component implementing them: one of the `roots` if any, otherwise
`default_implementation`.
"""
function closure(roots::Type...)
    order = Type[]
    visiting = Type[]

    function resolve(R)
        isabstracttype(R) || return R
        candidates = [C for C in roots if C <: R]
        length(candidates) > 1 &&
            error("role $(R) is implemented by more than one component: $(candidates)")
        isempty(candidates) || return only(candidates)
        return default_implementation(R)
    end

    function visit(T)
        C = resolve(T)
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
    Composite{T <: Tuple}

A value composed of parts, one per component. Properties are forwarded to the
part that has a field of that name, so `c.x` works for any field `x` of any
part.
"""
struct Composite{T <: Tuple}
    parts::T
end

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
# Index of the part that is (or implements) `T`. Computed at compile time.
@generated function _index(::Type{P}, ::Type{T}) where {P <: Tuple, T}
    i = findfirst(X -> X <: T, fieldtypes(P))
    i === nothing ? :(error("no component of type $(T)")) : i
end

"""
    component(c::Composite, T)

The part of `c` that is of type `T`, or that implements role `T`.
"""
component(c::Composite, ::Type{T}) where {T} = parts(c)[_index(typeof(parts(c)), T)]

"""
    map_components(f, c::Composite)

Apply `f` to every part of `c` and compose the results that aren't `nothing`.
"""
map_components(f, c::Composite) = Composite(Tuple(filter(!isnothing, map(f, parts(c)))))
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#composition-construct>>[init]
"""
    Composite{T}(; kwargs...)

Construct a composite from flat keyword arguments. Each keyword goes to the
part that has a field of that name.
"""
function (::Type{Composite{T}})(; kwargs...) where {T <: Tuple}
    types = fieldtypes(T)
    known = Set(Iterators.flatten(fieldnames.(types)))
    unknown = setdiff(keys(kwargs), known)
    isempty(unknown) || error("unknown arguments: $(join(unknown, ", "))")
    return Composite{T}(map(types) do P
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
    return Composite{Tuple{components...}}
end
# ~/~ end

end
# ~/~ end
