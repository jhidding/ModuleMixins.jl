# Objects, Inheritance and Modules in Julia

Julia is an amazing programming language that finds its use mainly in the hands of scientific modelers. Julia combines a welcoming syntax that doesn't scare new users with stellar performance rivaling C++ and Fortran. While Julia is easy to get into – the basics are a hybrid between Python and Matlab – there are some quirks to the language that change the way you need to think about overall program architecture: there are no objects. However, don't be discouraged: there is a reason for everything. I'll explain not only how we can work around the lack of objects, but also to embrace it! Last but not least, I present a new module to plug the final hole in the sea of abstractions that is left by the absence of objects: mixins, but more on that later.

## The JIT compiler

Julia aims to be both user-friendly and fast to execute. To achieve this, we get the wonderful mix of a dynamically typed language that is compiled to machine instructions, just-in-time (JIT). This works as follows: when a function is called we know the types of the arguments (the type signature) that are given as input, and the compiler generates optimized code for that specific type signature. When the function is called again with the same signature, the compiled version is reused from cache.

### Multiple dispatch

Since the type signature is such an integral part of the execution model, there is a nice trick we can play: multiple dispatch. We can redefine the same method for many different type signatures (similar to function overloading in C++). For instance, the addition operator has (as of Julia 1.10) 189 method implementations.

### Multiple dispatch supersedes objects

Multiple dispatch leads us to our first comparison with object oriented languages: abstract method calls are a dispatch on just the first parameter (self or this). In this respect the level of abstraction that multiple dispatch offers is more powerful than the idea of tying method implementations to compound types (i.e. objects). However, object oriented programming is more than just objects. Let's see how Julia compares.

## Object Oriented Programming

Object Oriented Programming as we know it today is a group of abstractions guided around the principle of having some way to dynamically look-up a method implementation for some object. I know this skips over the origin and abstract concepts around objects as they were found in the Smalltalk language, but that is besides the point. OOP as we know it is mostly designed around a mostly  antiquated run-time involving pointers and vtables. What I'm getting at, is that the abstractions in a language are often very much guided by the underlying run-time implementation. That means that in C++ the idea of classes makes sense. In Python we already have a very different view of an object, as everything is based around objects being hashmaps with some commonly understood interface. In Julia, having such a different run-time, multiple dispatch makes sense. Quite similar to the idea that the kind of music we make or hear depends on the setting in which it is staged (opera house without electric amplification, a living room setting, a noisy café or earbuds on a daily commute) and the available technology, more so than other cultural considerations.
Meanwhile, we have entire schools of thought on how to organise code and design architectures around larger code bases. These ideas have been heavily influenced by the tools of the time: Java and C++. So, all that considered, what do we understand by Object Oriented Programming?

- Compartimenting program state: data hiding, modularization
- Message passing between objects: similar to above, an object's behaviour can be completely understood from the way we poke sticks at it.
- Abstraction over interfaces: the interface is the outer shell of an object. If the implementations are widely different but the interface is the same, we can freely interchange objects of different types in cases of heterogeneous data.
- Inheritance or composition: we can use smaller objects to build larger ones. This can be done by inheritance, whereby the larger object behaves the same as the smaller one, except it can do more. The other way is by composition: we wrap the smaller object into the larger one, defining a new interface, but retaining the functionality.

In Julia we can achieve all these goals with multiple dispatch, except inheritance. Keep in mind that Julia is a dynamically typed language. Not only that, it fully embraces being dynamically typed through the dispatch mechanism.

## Functions, Methods, Interfaces

Ok, now we know: Julia doesn't have classes. How do we then organize our code? What are the means of abstraction? A common pattern is to define methods around types with similar utility. Suppose we want to write our own collection type, say a circular buffer that overwrites itself, only remembering the last $n$ items that were added.

```julia
mutable struct CircularBuffer{T}
    content::Vector{T}
    endloc::Int
    length::Int
end

CircularBuffer{T}(size::Int) where T =
    CircularBuffer{T}(Vector{T}(undef, size), 1, 0)
```

If we want `CircularBuffer` to behave like other collections in Julia, we need to define some methods.

```julia
Base.isempty(b::CircularBuffer{T}) where T = b.length == 0

function Base.empty!(b::CircularBuffer{T}) where T
    b.length = 0
    b.endloc = 1
end

Base.length(b::CircularBuffer{T}) where T = b.length
Base.checked_length(b::CircularBuffer{T}) where T = b.length
```

Here we see that we can make methods that are in the standard library operate on our own custom types.

The weakness in this approach is that none of this is checked at compile time.

## Composition over Inheritance

Suppose we're developing something of a graphics library. We have defined a type to work with points:

```julia
struct Point
    x::Float64
    y::Float64
end

Base.:+(a::Point, b::Point) = Point(a.x+b.x, a.y+b.y)
```

Now, we want to add colour to our points. We have a colour type that stores colour as an RGB triple. For convenience, we'll even throw in an abstract type `AbstractColour`

```julia
struct Colour
    r::Float64
    g::Float64
    b::Float64
end
```

We could do the following:

```julia
struct ColouredPoint
    x::Float64
    y::Float64
    colour::Colour
end
```

For the `Point` type we had defined an addition operator. How would you define that for the `ColouredPoint`? How do we handle the colour information?

In this example it is quite obvious that the better other option is to use **composition**.

```julia
struct ColouredPoint
    point::Point
    colour::Colour
end
```

In general, for most cases it is considered best practice to prefer composition over inheritance. Good for us, since Julia does not implement inheritance.

## Composing Modules

Now I present another example which requires a different form of inheritance, and is not so easily expressed using object composition (of the kind shown above). Moreover, we'll see that we can combine the idea of an **interface** in Julia with that of a **module**, creating something that works much the same as a class in other languages.

We need to get an overview of the problem: we'll implement a simple physics model, first without any abstraction. Then we'll use modules and mixins to restructure that code.

Our model has an `Input` structure to store all the parameters, and a `State` structure that is updated on every iteration. We may start with a monolithic implementation of a model of a bouncing weight on a spring. The spring exerts a force proportional to the position of the weight.

```julia
#| file: examples/just_a_spring.jl
module Spring

using Unitful

<<just-a-spring>>

end

module Script
    <<run-model>>
end

Script.main()
```

First of all, the input structure: we need to specify the properties of the spring (spring constant, and weight of the moving object), the specifics of our time integration (in this case, the time step and final time), and the initial conditions. In a larger model there will be many more parameters.

```julia
#| id: just-a-spring
@kwdef struct Input
    initial_position::typeof(1.0u"m")
    spring_constant::typeof(1.0u"N/m")
    weight::typeof(1.0u"kg")
    time_step::typeof(1.0u"s")
    time_end::typeof(1.0u"s")
end
```

A typical model will have some mutable `State`.

```julia
#| id: just-a-spring
@kwdef mutable struct State
    time::typeof(1.0u"s")
    position::typeof(1.0u"m")
    velocity::typeof(1.0u"m/s")
end
```

The first state is created from the given input.

```julia
#| id: just-a-spring
init(input::Input) = State(
    time=0.0u"s",
    position=input.initial_position,
    velocity=0.0u"m/s")
```

Then we `step!` over this state, until some condition is met.

```julia
#| id: just-a-spring
function step!(input::Input, state::State)
    Δt = input.time_step
    Δx = state.velocity * Δt
    Δv = -state.position * input.spring_constant / input.weight * Δt

    state.time += Δt
    state.position += Δx
    state.velocity += Δv
end
```

### First class modules

In Julia, modules are first-class objects, meaning they can be passed around same as integers or functions. Given that we expect a module to have an `init` and `step!` function as well as a `State` type, we can write a generic function for running our model.

```julia
#| id: run-model
function run(model::Module, input)
 state = model.init(input)
 Channel{model.State}() do ch
  while state.time < input.time_end
   model.step!(input, state)
   put!(ch, deepcopy(state))
  end
 end
end

function plot_result(model::Module, output)
    times = [f.time for f in output]
    pos = [f.position for f in output]

    fig = Figure()
    ax = Axis(fig[1, 1];
  dim1_conversion=Makie.UnitfulConversion(u"s"),
  dim2_conversion=Makie.UnitfulConversion(u"m"))
    lines!(ax, times, pos)
 fig
end

function main()
    input = Input(
        time_step = 0.01u"s",
        time_end = 5.0u"s",
        spring_constant = 50.0u"N/m",
        initial_position = 1.0u"m",
        weight = 1.0u"kg"
    )

    output = run(input) |> collect
    fig = plot_result(output)
    save("docs/src/just-a-spring.svg", fig)
end
```

### With Mixins

## Resources

- [Matthijs Cox's blog post on fruity design patterns](https://scientificcoder.com/fruity-composable-design-patterns-in-julia)
