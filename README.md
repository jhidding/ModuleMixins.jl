# ModuleMixins

[![Stable Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://jhidding.github.io/ModuleMixins.jl/stable)
[![In development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://jhidding.github.io/ModuleMixins.jl/dev)
[![Build Status](https://github.com/jhidding/ModuleMixins.jl/workflows/Test/badge.svg)](https://github.com/jhidding/ModuleMixins.jl/actions)
[![Test workflow status](https://github.com/jhidding/ModuleMixins.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/jhidding/ModuleMixins.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Lint workflow Status](https://github.com/jhidding/ModuleMixins.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/jhidding/ModuleMixins.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/jhidding/ModuleMixins.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/jhidding/ModuleMixins.jl/actions/workflows/Docs.yml?query=branch%3Amain)

[![Coverage](https://codecov.io/gh/jhidding/ModuleMixins.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/jhidding/ModuleMixins.jl)
[![DOI](https://zenodo.org/badge/DOI/FIXME)](https://doi.org/FIXME)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)
[![All Contributors](https://img.shields.io/github/all-contributors/jhidding/ModuleMixins.jl?labelColor=5e1ec7&color=c0ffee&style=flat-square)](#contributors)

`ModuleMixins` is a way of composing families of `struct` definitions on a module level. Suppose we have several modules that contain structs of the same name. We can compose these modules such that all the structs they have in common are merged. Methods that work on one component should now work on the composed type.

```julia
using ModuleMixins

@compose module A
  struct S
    a
  end
end

@compose module B
  @mixin A

  struct S
    b
  end
end

@assert fieldnames(B.S) == (:a, :b)
```

See the [full documentation](https://jhidding.github.io/ModuleMixins.jl/).

## How to Cite

If you use ModuleMixins.jl in your work, please cite using the reference given in [CITATION.cff](https://github.com/jhidding/ModuleMixins.jl/blob/main/CITATION.cff).


## Contributing

If you want to make contributions of any kind, please first that a look into our [contributing guide directly on GitHub](docs/src/90-contributing.md) or the [contributing page on the website](https://jhidding.github.io/ModuleMixins.jl/dev/90-contributing/).


---

### Contributors

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
