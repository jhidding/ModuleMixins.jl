# ~/~ begin <<docs/src/50-implementation.md#src/Constructors.jl>>[init]
module Constructors

using MacroTools: @capture
using .Iterators: repeated

import ..Passes: Pass, pass, no_match
import ..Structs: Struct

# ~/~ begin <<docs/src/50-implementation.md#constructor-pass>>[init]
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
    @assert (
        @capture(f, function name_(args__)::return_type_name_[fields__] body__ end) ||
        @capture(f, name_(args__)::return_type_name_[fields__] = body__)
    ) "constructor expression doesn't match short or long form function:\n $f"
    n_args = length(args)
    arg_names = [arg_name(a) for a in args]
    expr = :(function ($(arg_names...),) $(body...) end)
    return Constructor(name, arg_names, return_type_name, [fields => expr])
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#constructor-pass>>[1]
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
# ~/~ end

end
# ~/~ end
