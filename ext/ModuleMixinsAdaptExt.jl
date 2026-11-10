# ~/~ begin <<docs/src/41-composition.md#ext/ModuleMixinsAdaptExt.jl>>[init]
module ModuleMixinsAdaptExt

using Adapt: Adapt, adapt
using ModuleMixins.Procedural: Composite, parts

function Adapt.adapt_structure(to, c::Composite{T, R}) where {T, R}
    adapted = map(p -> adapt(to, p), parts(c))
    return Composite{typeof(adapted), R}(adapted)
end

end
# ~/~ end
