# ~/~ begin <<docs/src/40-studies.md#src/Lambda.jl>>[init]
module Lambda
    using MacroTools: @capture
    import ..Passes: Pass, pass, no_match, walk
    export @lambda, @instantiate

    struct Parameter
        name::Symbol
        has_default::Bool
        default::Any
    end

    name(par) = par.name
    has_default(parameter) = parameter.has_default

    function make_parameter(expr)
        if @capture(expr, name_ = default_)
            return Parameter(name, true, default)
        elseif expr isa Symbol
            return Parameter(expr, false, nothing)
        else
            return nothing
        end
    end

    struct Argument
        name::Union{Symbol, Nothing}
        value::Any
    end

    positional(argument) = argument.name === nothing

    make_argument(mod) = function (expr)
        value = if @capture(expr, name_ = value_)
            value
        else
            expr
        end
        return Argument(name, @eval(mod, $(value)))
    end

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
        bindings = Iterators.flatten((positional_bindings, keyword_bindings)) |> collect
        @assert(name.(pars) == name.(bindings))
        return bindings
    end

    function as_expression(bv::BoundVariable)
        return :(const $(bv.name) = $(bv.value))
    end

    struct ModuleTemplate
        name::Symbol
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
        println("module $(name) with parameters $(parameters)")
        template = ModuleTemplate(name, parameters, body[2:end])
        return esc(:(const $name = $template))
    end

    macro instantiate(expr)
        @assert @capture(expr, instance_name_ = template_name_{raw_arguments__})
        arguments = raw_arguments .|> make_argument(__module__)
        template = getfield(__module__, template_name)
        bound_vars = bind(template.parameters, arguments)
        return esc(Expr(:toplevel, :(module $(instance_name)
            const AST = $(template.body)
            $(as_expression.(bound_vars)...)
            $(template.body...)
        end)))
    end
end
# ~/~ end
