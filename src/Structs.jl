# ~/~ begin <<docs/src/50-implementation.md#src/Structs.jl>>[init]
module Structs

using MacroTools: @capture, postwalk
import ..Passes: Pass, pass, no_match

# ~/~ begin <<docs/src/50-implementation.md#struct-data>>[init]
mutable struct Struct
    use_kwdef::Bool
    is_mutable::Bool
    name::Symbol
    type_parameters::Union{Vector{Symbol},Nothing}
    abstract_type::Union{Symbol,Nothing}
    fields::Vector{Union{Expr,Symbol}}
end
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#struct-data>>[1]
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
# ~/~ end
# ~/~ begin <<docs/src/50-implementation.md#collect-struct-pass>>[init]
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
# ~/~ end

end
# ~/~ end
