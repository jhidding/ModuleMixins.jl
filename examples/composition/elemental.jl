# ~/~ begin <<docs/src/41-composition.md#examples/composition/elemental.jl>>[init]
using ModuleMixins.Procedural
import ModuleMixins.Procedural: requires, implements, default_implementation
using Test

# ~/~ begin <<docs/src/41-composition.md#elemental-components>>[init]
abstract type AbstractSource end
function value end

module Constant
    import ..AbstractSource, ..value, ..implements
    @kwdef struct Input
        c::Float64 = 1.0
    end
    implements(::Val{Constant}, ::Type{AbstractSource}) = true
    value(s::Input, model) = s.c
end

module Ramp
    import ..AbstractSource, ..value, ..implements
    @kwdef struct Input
        slope::Float64 = 1.0
        x::Float64 = 0.0
    end
    implements(::Val{Ramp}, ::Type{AbstractSource}) = true
    value(s::Input, model) = s.slope * s.x
end

default_implementation(::Type{AbstractSource}) = Constant
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#elemental-components>>[1]
module Double
    import ..AbstractSource, ..value, ..requires
    using ModuleMixins.Procedural: component
    @kwdef struct Input
        factor::Float64 = 2.0
    end
    requires(::Val{Double}) = (AbstractSource,)
    value(d::Input, model) = d.factor * value(component(model, AbstractSource), model)
end

module Square
    import ..AbstractSource, ..value, ..requires
    using ModuleMixins.Procedural: component
    struct Input end
    requires(::Val{Square}) = (AbstractSource,)
    value(::Input, model) = value(component(model, AbstractSource), model)^2
end

module Sum
    import ..value, ..requires
    using ModuleMixins.Procedural: component
    import ..Double, ..Square
    struct Input end
    requires(::Val{Sum}) = (Double, Square)
    value(::Input, model) =
        value(component(model, Double.Input), model) +
        value(component(model, Square.Input), model)
end
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#elemental-run>>[init]
@show closure(Sum)

const Model = record_type(:Input, Sum)
m = Model(c = 3.0, factor = 10.0)
@show m
@show m.c m.factor
@show value(component(m, Sum.Input), m)
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#elemental-run>>[1]
const RampModel = record_type(:Input, Sum, Ramp)
@show closure(Sum, Ramp)
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
@test_throws ErrorException record_type(:Input, Sum, Ramp, Constant)
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#elemental-run>>[3]
abstract type AbstractGradient end
function gradient end

gradient(s::Ramp.Input, model) = s.slope
implements(::Val{Ramp}, ::Type{AbstractGradient}) = true

module Slope
    import ..AbstractGradient, ..value, ..gradient, ..requires
    using ModuleMixins.Procedural: component
    struct Input end
    requires(::Val{Slope}) = (AbstractGradient,)
    value(::Input, model) = gradient(component(model, AbstractGradient), model)
end
# ~/~ end
# ~/~ begin <<docs/src/41-composition.md#elemental-run>>[4]
const BothModel = record_type(:Input, Sum, Slope, Ramp)
@show closure(Sum, Slope, Ramp)
b = BothModel(slope = 2.0, x = 1.5)
@show value(component(b, Sum.Input), b)
@show value(component(b, Slope.Input), b)
@test component(b, AbstractSource) === component(b, AbstractGradient)

@inferred value(component(b, Slope.Input), b)
@test_throws ErrorException record_type(:Input, Sum, Slope)
println("all checks passed")
# ~/~ end
# ~/~ end
