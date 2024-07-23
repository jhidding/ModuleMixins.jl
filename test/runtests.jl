using ModuleMixins.jl
using Test

@testset "ModuleMixins.jl.jl" begin
  @test ModuleMixins.jl.hello_world() == "Hello, World!"
end
