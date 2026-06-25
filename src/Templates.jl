# ~/~ begin <<docs/src/40-studies.md#src/Templates.jl>>[init]
module Templates
    using MacroTools: @capture
    export @lambda, @instantiate

    # ~/~ begin <<docs/src/40-studies.md#template-parameter>>[init]
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
    # ~/~ end
    # ~/~ begin <<docs/src/40-studies.md#template-argument>>[init]
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
    # ~/~ end
    # ~/~ begin <<docs/src/40-studies.md#template-bound-variable>>[init]
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
    # ~/~ end

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
        template = ModuleTemplate(name, __module__, parameters, body[2:end], Ref{Int}(0))
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
# ~/~ end
