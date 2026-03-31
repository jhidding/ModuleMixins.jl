# ~/~ begin <<docs/src/50-implementation.md#test/runtests.jl>>[init]
using Test

@testset "ModuleMixins.jl" begin
    include("SpecSpec.jl")
    include("PassesSpec.jl")
    include("MixinsSpec.jl")
    include("StructsSpec.jl")
    include("ConstructorsSpec.jl")
    include("ComposeSpec.jl")
end
# ~/~ end
