```@meta
CurrentModule = ModuleMixins
```

# ModuleMixins

Documentation for [ModuleMixins](https://github.com/jhidding/ModuleMixins.jl).

`ModuleMixins` is a way of composing families of `struct` definitions on a module level. Suppose we have several modules that contain structs of the same name. We can compose these modules such that all the structs they have in common are merged. Methods that work on one component should now work on the composed type.

!!! note "Redesign"
    The first versions of this module worked completely at a syntactic level. The entire AST of each component was stored and used to merge modules. This non-local approach to macro programming didn't play so well with Revise and also had other limitations.

    The new design is completely procedural. Composite `struct` definitions are built from their direct parts and transitive dependencies, all of which are stored compile time using clever dispatch lookup. As an added layer, we provide some light-weight macros to reduce the amount of boiler plate in this approach.

1. [Procedural Tutorial](15-tutorial.md)
2. [Syntactic Tutorial](16-tutorial-syntax.md)
3. [Procedural Implementation](41-composition.md)
4. [Syntactic Implementation](42-composition-syntax.md)

## Contributors

```@raw html
<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
```
