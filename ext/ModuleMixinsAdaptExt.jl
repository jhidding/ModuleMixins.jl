# ~/~ begin <<docs/src/41-composition.md#ext/ModuleMixinsAdaptExt.jl>>[init]
module ModuleMixinsAdaptExt

using Adapt: Adapt, adapt
using ModuleMixins.Procedural: Composite, map_components

Adapt.adapt_structure(to, c::Composite) = map_components(p -> adapt(to, p), c)

end
# ~/~ end
