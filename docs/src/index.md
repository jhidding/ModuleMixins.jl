```@meta
CurrentModule = ModuleMixins
```

# ModuleMixins

Documentation for [ModuleMixins](https://github.com/jhidding/ModuleMixins.jl).

`ModuleMixins` is a way of composing families of `struct` definitions on a module level. Suppose we have several modules that contain structs of the same name. We can compose these modules such that all the structs they have in common are merged. Methods that work on one component should now work on the composed type.

!!! info
    Most problems with object type abstraction can be solved in Julia by cleverly using abstract types and multiple dispatch. Use `ModuleMixins` only after you have convinced yourself you absolutely need it.

## Contributors

```@raw html
<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
```
