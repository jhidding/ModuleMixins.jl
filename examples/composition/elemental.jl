# ~/~ begin <<docs/src/41-composition.md#examples/composition/elemental.jl>>[init]
include("composition.jl")
using .Composition
import .Composition: requires, default_implementation
using Test

# ~/~ begin <<docs/src/41-composition.md#elemental-components>>[init]
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
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#elemental-components>>[1]
module Double
    import ..AbstractSource, ..value, ..requires
    using ..Composition: component
    @kwdef struct Input
        factor::Float64 = 2.0
    end
    requires(::Type{Input}) = (AbstractSource,)
    value(d::Input, model) = d.factor * value(component(model, AbstractSource), model)
end

module Square
    import ..AbstractSource, ..value, ..requires
    using ..Composition: component
    struct Input end
    requires(::Type{Input}) = (AbstractSource,)
    value(::Input, model) = value(component(model, AbstractSource), model)^2
end

module Sum
    import ..value, ..requires
    using ..Composition: component
    import ..Double, ..Square
    struct Input end
    requires(::Type{Input}) = (Double.Input, Square.Input)
    value(::Input, model) =
        value(component(model, Double.Input), model) +
        value(component(model, Square.Input), model)
end
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#elemental-run>>[init]
@show closure(Sum.Input)

const Model = model_type(Sum.Input)
m = Model(c = 3.0, factor = 10.0)
@show m
@show m.c m.factor
@show value(component(m, Sum.Input), m)
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#elemental-run>>[1]
const RampModel = model_type(Sum.Input, Ramp.Input)
@show closure(Sum.Input, Ramp.Input)
r = RampModel(slope = 2.0, x = 1.5)
@show value(component(r, Sum.Input), r)
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#elemental-run>>[2]
get_c(m) = m.c
get_slope(m) = m.slope
@inferred get_c(m)
@inferred get_slope(r)
@inferred value(component(r, Sum.Input), r)

@test_throws ErrorException Model(colour = :red)
@test_throws ErrorException model_type(Sum.Input, Ramp.Input, Constant.Input)
println("all checks passed")
# ~/~ end
# ~/~ end
