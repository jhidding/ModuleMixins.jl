# ~/~ begin <<docs/src/42-composition-syntax.md#examples/composition/gpu.jl>>[init]
using ModuleMixins.Syntactic
using ModuleMixins.Procedural
using Adapt
using KernelAbstractions

const backend_name = get(ARGS, 1, "cpu")
if backend_name == "cuda"
    using CUDA
elseif backend_name == "oneapi"
    using oneAPI
end

const DeviceArray =
    backend_name == "cuda" ? CUDA.CuArray :
    backend_name == "oneapi" ? oneAPI.oneArray :
    Array

@component module Grid
    using Adapt

    @kwdef struct Input
        n::Int
        dt::Float32 = 0.1f0
    end

    @kwdef struct State{Storage <: AbstractVector{Float32}}
        height::Storage
    end

    Adapt.@adapt_structure State
end

@component module Growth
    using Adapt
    @mixin Grid

    @kwdef struct Input
        rate::Float32
    end

    @kwdef struct State{Storage <: AbstractVector{Float32}}
        factor::Storage
    end

    Adapt.@adapt_structure State
end

@kernel function step_kernel!(state, input)
    i = @index(Global)
    @inbounds state.height[i] += input.dt * input.rate * state.factor[i]
end

const Input = record_type(:Input, Growth)
const HostState = record_type(:State, Growth; Storage = Vector{Float32})

input = Input(n = 1024, rate = 2.0f0)
host = HostState(
    height = zeros(Float32, input.n),
    factor = collect(range(0.0f0, 1.0f0, length = input.n)))

state = adapt(DeviceArray, host)
println("storage: ", typeof(component(state, Grid).height))

backend = get_backend(state.height)
step! = step_kernel!(backend)
for _ in 1:10
    step!(state, input; ndrange = input.n)
end
KernelAbstractions.synchronize(backend)

result = adapt(Array, state)
println("result isa HostState: ", result isa HostState)
println("final height: ", result.height[end])
# ~/~ end
