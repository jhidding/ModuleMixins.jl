var documenterSearchIndex = {"docs":
[{"location":"50-implementation/#Implementation","page":"Implementation","title":"Implementation","text":"","category":"section"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"The way ModuleMixins is implemented, is that we start out with something relatively simple, and build out from that. This means there will be some redudant code. Macros are hard to engineer, this takes you through the entire process.","category":"page"},{"location":"50-implementation/#Prelude","page":"Implementation","title":"Prelude","text":"","category":"section"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| file: src/ModuleMixins.jl\nmodule ModuleMixins\n\nusing MacroTools: @capture, postwalk, prewalk\n\nexport @compose\n\n<<spec>>\n<<mixin>>\n<<struct-data>>\n<<compose>>\n\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"To facilitate testing, we need to be able to compare syntax. We use the clean function to remove source information from expressions.","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| file: test/runtests.jl\nusing Test\nusing ModuleMixins:\n    @spec,\n    @spec_mixin,\n    @spec_using,\n    @mixin,\n    Struct,\n    parse_struct,\n    define_struct,\n    Pass,\n    @compose\nusing MacroTools: prewalk, rmlines\n\nclean(expr) = prewalk(rmlines, expr)\n\n<<test-toplevel>>\n\n@testset \"ModuleMixins\" begin\n    <<test>>\nend","category":"page"},{"location":"50-implementation/#@spec","page":"Implementation","title":"@spec","text":"","category":"section"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"The @spec macro creates a new module, and stores its own AST inside that module.","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test-toplevel\n@spec module MySpec\nconst msg = \"hello\"\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test\n@testset \"@spec\" begin\n    @test clean.(MySpec.AST) == clean.([:(const msg = \"hello\")])\n    @test MySpec.msg == \"hello\"\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"The @spec macro is used to specify the structs of a model component.","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: spec\n\"\"\"\n    @spec module *name*\n        *body*...\n    end\n\nCreate a spec. The `@spec` macro itself doesn't perform any operations other than creating a module and storing its own AST as `const *name*.AST`.\n\"\"\"\nmacro spec(mod)\n    @assert @capture(mod, module name_\n    body__\n    end)\n\n    esc(Expr(:toplevel, :(module $name\n    $(body...)\n    const AST = $body\n    end)))\nend","category":"page"},{"location":"50-implementation/#@spec_mixin","page":"Implementation","title":"@spec_mixin","text":"","category":"section"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"We now add the @mixin syntax. This still doesn't do anything, other than storing the names of parent modules.","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test-toplevel\n@spec_mixin module MyMixinSpecOne\n@mixin A\nend\n@spec_mixin module MyMixinSpecMany\n@mixin A, B, C\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test\n@testset \"@spec_mixin\" begin\n    @test MyMixinSpecOne.PARENTS == [:A]\n    @test MyMixinSpecMany.PARENTS == [:A, :B, :C]\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"Here's the @mixin macro:","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: mixin\nmacro mixin(deps)\n    if @capture(deps, (multiple_deps__,))\n        esc(:(const PARENTS = [$(QuoteNode.(multiple_deps)...)]))\n    else\n        esc(:(const PARENTS = [$(QuoteNode(deps))]))\n    end\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"The QuoteNode calls prevent the symbols from being evaluated at macro expansion time. We need to make sure that the @mixin syntax is also available from within the module.","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: spec\n\nmacro spec_mixin(mod)\n    @assert @capture(mod, module name_\n    body__\n    end)\n\n    esc(Expr(:toplevel, :(module $name\n    import ..@mixin\n\n    $(body...)\n\n    const AST = $body\n    end)))\nend","category":"page"},{"location":"50-implementation/#@spec_using","page":"Implementation","title":"@spec_using","text":"","category":"section"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"I can't think of any usecase where a @mixin A, doesn't also mean using ..A. By replacing the @mixin with a using statement, we also no longer need to import @mixin. In fact, that macro becomes redundant. Also, in @spec_using we're allowed multiple @mixin statements.","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test-toplevel\n@spec_using module SU_A\nconst X = :hello\nexport X\nend\n\n@spec_using module SU_B\n@mixin SU_A\nconst Y = X\nend\n\n@spec_using module SU_C\nconst Z = :goodbye\nend\n\n@spec_using module SU_D\n@mixin SU_A\n@mixin SU_B, SU_C\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test\n@testset \"@spec_using\" begin\n    @test SU_B.Y == SU_A.X\n    @test SU_B.PARENTS == [:SU_A]\n    @test SU_D.PARENTS == [:SU_A, :SU_B, :SU_C]\n    @test SU_D.SU_C.Z == :goodbye\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"We now use the postwalk function (from MacroTools.jl) to transform expressions and collect information into searchable data structures. We make a little abstraction over the postwalk function, so we can compose multiple transformations in a single tree walk.","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test-toplevel\nstruct EmptyPass <: Pass\n    tag::Symbol\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test\n@testset \"pass composition\" begin\n    a = EmptyPass(:a) + EmptyPass(:b)\n    @test a.parts[1].tag == :a\n    @test a.parts[2].tag == :b\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"A composite pass tries all of its parts in order, returning the value of the first pass that doesn't return nothing.","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: spec\n\nabstract type Pass end\n\nfunction pass(x::Pass, expr)\n    error(\"Can't call `pass` on abstract `Pass`.\")\nend\n\nstruct CompositePass <: Pass\n    parts::Vector{Pass}\nend\n\nBase.:+(a::CompositePass...) = CompositePass(splat(vcat)(getfield.(a, :parts)))\nBase.convert(::Type{CompositePass}, a::Pass) = CompositePass([a])\nBase.:+(a::Pass...) = splat(+)(convert.(CompositePass, a))\n\nfunction pass(cp::CompositePass, expr)\n    for p in cp.parts\n        result = pass(p, expr)\n        if result !== :nomatch\n            return result\n        end\n    end\n    return :nomatch\nend\n\nfunction walk(x::Pass, expr_list)\n    function patch(expr)\n        result = pass(x, expr)\n        result === :nomatch ? expr : result\n    end\n    prewalk.(patch, expr_list)\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: spec\n@kwdef struct MixinPass <: Pass\n    items::Vector{Symbol}\nend\n\nfunction pass(m::MixinPass, expr)\n    @capture(expr, @mixin deps_) || return :nomatch\n\n    if @capture(deps, (multiple_deps__,))\n        append!(m.items, multiple_deps)\n        :(\n            begin\n                $([:(using ..$d) for d in multiple_deps]...)\n            end\n        )\n    else\n        push!(m.items, deps)\n        :(using ..$deps)\n    end\nend\n\nmacro spec_using(mod)\n    @assert @capture(mod, module name_ body__ end)\n\n    parents = MixinPass([])\n    clean_body = walk(parents, body)\n\n    esc(Expr(:toplevel, :(module $name\n        $(clean_body...)\n        const AST = $body\n        const PARENTS = [$(QuoteNode.(parents.items)...)]\n    end)))\nend","category":"page"},{"location":"50-implementation/#Structure-of-structs","page":"Implementation","title":"Structure of structs","text":"","category":"section"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"We'll convert struct syntax into collectable data, then convert that back into structs again. We'll support several patterns:","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test\ncases = Dict(\n    :(struct A x end) => Struct(false, false, :A, nothing, [:x]),\n    :(mutable struct A x end) => Struct(false, true, :A, nothing, [:x]),\n    :(@kwdef struct A x end) => Struct(true, false, :A, nothing, [:x]),\n    :(@kwdef mutable struct A x end) => Struct(true, true, :A, nothing, [:x]),\n)\n\nfor (k, v) in pairs(cases)\n    @testset \"Struct mangling: $(join(split(string(clean(k))), \" \"))\" begin\n        @test clean(define_struct(parse_struct(k))) == clean(k)\n        @test clean(define_struct(v)) == clean(k)\n    end\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"Each of these can have either just a Symbol for a name, or a A <: B expression. This is a bit cumbersome, but we'll have to deal with all of these cases.","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test\n@testset \"Struct mangling abstracts\" begin\n    @test parse_struct(:(struct A <: B x end)).abstract_type == :B\n    @test parse_struct(:(mutable struct A <: B x end)).abstract_type == :B\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: struct-data\n\nstruct Struct\n    use_kwdef::Bool\n    is_mutable::Bool\n    name::Symbol\n    abstract_type::Union{Symbol,Nothing}\n    fields::Vector{Union{Expr,Symbol}}\nend\n\nfunction extend_struct!(s1::Struct, s2::Struct)\n    append!(s1.fields, s2.fields)\nend\n\nfunction parse_struct(expr)\n    @capture(expr, (@kwdef kw_struct_expr_) | struct_expr_)\n    uses_kwdef = kw_struct_expr !== nothing\n    struct_expr = uses_kwdef ? kw_struct_expr : struct_expr\n\n    @capture(struct_expr,\n        (struct name_ fields__ end) |\n        (mutable struct mut_name_ fields__ end)) || return\n\n    is_mutable = mut_name !== nothing\n    sname = is_mutable ? mut_name : name\n    @capture(sname, (name_ <: abst_) | name_)\n\n    return Struct(uses_kwdef, is_mutable, name, abst, fields)\nend\n\nfunction define_struct(s::Struct)\n    name = s.abstract_type !== nothing ? :($(s.name) <: $(s.abstract_type)) : s.name\n    sdef = if s.is_mutable\n        :(mutable struct $name\n            $(s.fields...)\n        end)\n    else\n        :(struct $name\n            $(s.fields...)\n        end)\n    end\n    s.use_kwdef ? :(@kwdef $sdef) : sdef\nend","category":"page"},{"location":"50-implementation/#@compose","page":"Implementation","title":"@compose","text":"","category":"section"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"Unfortunately now comes a big leap. We'll merge all struct definitions inside the body of a module definition with that of its parents. We must also make sure that a struct definition still compiles, so we have to take along using and const statements.","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test-toplevel\nmodule ComposeTest1\nusing ModuleMixins\n\n@compose module A\n    struct S\n        a::Int\n    end\nend\n\n@compose module B\n    struct S\n        b::Int\n    end\nend\n\n@compose module AB\n    @mixin A, B\nend\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: test\n@testset \"compose struct members\" begin\n    @test fieldnames(ComposeTest1.AB.S) == (:a, :b)\nend","category":"page"},{"location":"50-implementation/","page":"Implementation","title":"Implementation","text":"#| id: compose\n\nstruct CollectUsingPass <: Pass\n    items::Vector{Expr}\nend\n\nfunction pass(p::CollectUsingPass, expr)\n    @capture(expr, using x__ | using mod__: x__) || return :nomatch\n    push!(p.items, expr)\n    return nothing\nend\n\nstruct CollectConstPass <: Pass\n    items::Vector{Expr}\nend\n\nfunction pass(p::CollectConstPass, expr)\n    @capture(expr, const x_ = y_) || return :nomatch\n    push!(p.items, expr)\n    return nothing\nend\n\nstruct CollectStructPass <: Pass\n    items::IdDict{Symbol,Struct}\nend\n\nfunction pass(p::CollectStructPass, expr)\n    s = parse_struct(expr)\n    s === nothing && return :nomatch\n    if s.name in keys(p.items)\n        extend_struct!(p.items[s.name], s)\n    else\n        p.items[s.name] = s\n    end\n    return nothing\nend\n\nmacro compose(mod)\n    @assert @capture(mod, module name_ body__ end)\n\n    mixins = Symbol[]\n    parents = MixinPass([])\n    usings = CollectUsingPass([])\n    consts = CollectConstPass([])\n    structs = CollectStructPass(IdDict())\n\n    function mixin(expr)\n        parents = MixinPass([])\n        pass1 = walk(parents, expr)\n        for p in parents.items\n            p in mixins && continue\n            push!(mixins, p)\n            parent_expr = Core.eval(__module__, :($(p).AST))\n            mixin(parent_expr)\n        end\n        walk(usings + consts + structs, pass1)\n    end\n\n    clean_body = mixin(body)\n\n    esc(Expr(:toplevel, :(module $name\n        $(usings.items...)\n        $(consts.items...)\n        $(define_struct.(values(structs.items))...)\n        $(clean_body...)\n        const AST = $body\n        const PARENTS = [$(QuoteNode.(parents.items)...)]\n    end)))\nend","category":"page"},{"location":"91-developer/#dev_docs","page":"Developer documentation","title":"Developer documentation","text":"","category":"section"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"note: Contributing guidelines\nIf you haven't, please read the Contributing guidelines first.","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"If you want to make contributions to this package that involves code, then this guide is for you.","category":"page"},{"location":"91-developer/#First-time-clone","page":"Developer documentation","title":"First time clone","text":"","category":"section"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"tip: If you have writing rights\nIf you have writing rights, you don't have to fork. Instead, simply clone and skip ahead. Whenever upstream is mentioned, use origin instead.","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"If this is the first time you work with this repository, follow the instructions below to clone the repository.","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"Fork this repo\nClone your repo (this will create a git remote called origin)\nAdd this repo as a remote:\ngit remote add upstream https://github.com/jhidding/ModuleMixins.jl","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"This will ensure that you have two remotes in your git: origin and upstream. You will create branches and push to origin, and you will fetch and update your local main branch from upstream.","category":"page"},{"location":"91-developer/#Linting-and-formatting","page":"Developer documentation","title":"Linting and formatting","text":"","category":"section"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"Install a plugin on your editor to use EditorConfig. This will ensure that your editor is configured with important formatting settings.","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"We use https://pre-commit.com to run the linters and formatters. In particular, the Julia code is formatted using JuliaFormatter.jl, so please install it globally first:","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"julia> # Press ]\npkg> activate\npkg> add JuliaFormatter","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"To install pre-commit, we recommend using pipx as follows:","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"# Install pipx following the link\npipx install pre-commit","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"With pre-commit installed, activate it as a pre-commit hook:","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"pre-commit install","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"To run the linting and formatting manually, enter the command below:","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"pre-commit run -a","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"Now, you can only commit if all the pre-commit tests pass.","category":"page"},{"location":"91-developer/#Testing","page":"Developer documentation","title":"Testing","text":"","category":"section"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"As with most Julia packages, you can just open Julia in the repository folder, activate the environment, and run test:","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"julia> # press ]\npkg> activate .\npkg> test","category":"page"},{"location":"91-developer/#Working-on-a-new-issue","page":"Developer documentation","title":"Working on a new issue","text":"","category":"section"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"We try to keep a linear history in this repo, so it is important to keep your branches up-to-date.","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"Fetch from the remote and fast-forward your local main\ngit fetch upstream\ngit switch main\ngit merge --ff-only upstream/main\nBranch from main to address the issue (see below for naming)\ngit switch -c 42-add-answer-universe\nPush the new local branch to your personal remote repository\ngit push -u origin 42-add-answer-universe\nCreate a pull request to merge your remote branch into the org main.","category":"page"},{"location":"91-developer/#Branch-naming","page":"Developer documentation","title":"Branch naming","text":"","category":"section"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"If there is an associated issue, add the issue number.\nIf there is no associated issue, and the changes are small, add a prefix such as \"typo\", \"hotfix\", \"small-refactor\", according to the type of update.\nIf the changes are not small and there is no associated issue, then create the issue first, so we can properly discuss the changes.\nUse dash separated imperative wording related to the issue (e.g., 14-add-tests, 15-fix-model, 16-remove-obsolete-files).","category":"page"},{"location":"91-developer/#Commit-message","page":"Developer documentation","title":"Commit message","text":"","category":"section"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"Use imperative or present tense, for instance: Add feature or Fix bug.\nHave informative titles.\nWhen necessary, add a body with details.\nIf there are breaking changes, add the information to the commit message.","category":"page"},{"location":"91-developer/#Before-creating-a-pull-request","page":"Developer documentation","title":"Before creating a pull request","text":"","category":"section"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"tip: Atomic git commits\nTry to create \"atomic git commits\" (recommended reading: The Utopic Git History).","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"Make sure the tests pass.\nMake sure the pre-commit tests pass.\nFetch any main updates from upstream and rebase your branch, if necessary:\ngit fetch upstream\ngit rebase upstream/main BRANCH_NAME\nThen you can open a pull request and work with the reviewer to address any issues.","category":"page"},{"location":"91-developer/#Building-and-viewing-the-documentation-locally","page":"Developer documentation","title":"Building and viewing the documentation locally","text":"","category":"section"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"Following the latest suggestions, we recommend using LiveServer to build the documentation. Here is how you do it:","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"Run julia --project=docs to open Julia in the environment of the docs.\nIf this is the first time building the docs\nPress ] to enter pkg mode\nRun pkg> dev . to use the development version of your package\nPress backspace to leave pkg mode\nRun julia> using LiveServer\nRun julia> servedocs()","category":"page"},{"location":"91-developer/#Making-a-new-release","page":"Developer documentation","title":"Making a new release","text":"","category":"section"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"To create a new release, you can follow these simple steps:","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"Create a branch release-x.y.z\nUpdate version in Project.toml\nUpdate the CHANGELOG.md:\nRename the section \"Unreleased\" to \"[x.y.z] - yyyy-mm-dd\" (i.e., version under brackets, dash, and date in ISO format)\nAdd a new section on top of it named \"Unreleased\"\nAdd a new link in the bottom for version \"x.y.z\"\nChange the \"[unreleased]\" link to use the latest version - end of line, vx.y.z ... HEAD.\nCreate a commit \"Release vx.y.z\", push, create a PR, wait for it to pass, merge the PR.\nGo back to main screen and click on the latest commit (link: https://github.com/jhidding/ModuleMixins.jl/commit/main)\nAt the bottom, write @JuliaRegistrator register","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"After that, you only need to wait and verify:","category":"page"},{"location":"91-developer/","page":"Developer documentation","title":"Developer documentation","text":"Wait for the bot to comment (should take < 1m) with a link to a RP to the registry\nFollow the link and wait for a comment on the auto-merge\nThe comment should said all is well and auto-merge should occur shortly\nAfter the merge happens, TagBot will trigger and create a new GitHub tag. Check on https://github.com/jhidding/ModuleMixins.jl/releases\nAfter the release is create, a \"docs\" GitHub action will start for the tag.\nAfter it passes, a deploy action will run.\nAfter that runs, the stable docs should be updated. Check them and look for the version number.","category":"page"},{"location":"95-reference/#reference","page":"Reference","title":"Reference","text":"","category":"section"},{"location":"95-reference/#Contents","page":"Reference","title":"Contents","text":"","category":"section"},{"location":"95-reference/","page":"Reference","title":"Reference","text":"Pages = [\"95-reference.md\"]","category":"page"},{"location":"95-reference/#Index","page":"Reference","title":"Index","text":"","category":"section"},{"location":"95-reference/","page":"Reference","title":"Reference","text":"Pages = [\"95-reference.md\"]","category":"page"},{"location":"95-reference/","page":"Reference","title":"Reference","text":"Modules = [ModuleMixins]","category":"page"},{"location":"95-reference/#ModuleMixins.@spec-Tuple{Any}","page":"Reference","title":"ModuleMixins.@spec","text":"@spec module *name*\n    *body*...\nend\n\nCreate a spec. The @spec macro itself doesn't perform any operations other than creating a module and storing its own AST as const *name*.AST.\n\n\n\n\n\n","category":"macro"},{"location":"90-contributing/#contributing","page":"Contributing guidelines","title":"Contributing guidelines","text":"","category":"section"},{"location":"90-contributing/","page":"Contributing guidelines","title":"Contributing guidelines","text":"First of all, thanks for the interest!","category":"page"},{"location":"90-contributing/","page":"Contributing guidelines","title":"Contributing guidelines","text":"We welcome all kinds of contribution, including, but not limited to code, documentation, examples, configuration, issue creating, etc.","category":"page"},{"location":"90-contributing/","page":"Contributing guidelines","title":"Contributing guidelines","text":"Be polite and respectful, and follow the code of conduct.","category":"page"},{"location":"90-contributing/#Bug-reports-and-discussions","page":"Contributing guidelines","title":"Bug reports and discussions","text":"","category":"section"},{"location":"90-contributing/","page":"Contributing guidelines","title":"Contributing guidelines","text":"If you think you found a bug, feel free to open an issue. Focused suggestions and requests can also be opened as issues. Before opening a pull request, start an issue or a discussion on the topic, please.","category":"page"},{"location":"90-contributing/#Working-on-an-issue","page":"Contributing guidelines","title":"Working on an issue","text":"","category":"section"},{"location":"90-contributing/","page":"Contributing guidelines","title":"Contributing guidelines","text":"If you found an issue that interests you, comment on that issue what your plans are. If the solution to the issue is clear, you can immediately create a pull request (see below). Otherwise, say what your proposed solution is and wait for a discussion around it.","category":"page"},{"location":"90-contributing/","page":"Contributing guidelines","title":"Contributing guidelines","text":"tip: Tip\nFeel free to ping us after a few days if there are no responses.","category":"page"},{"location":"90-contributing/","page":"Contributing guidelines","title":"Contributing guidelines","text":"If your solution involves code (or something that requires running the package locally), check the developer documentation. Otherwise, you can use the GitHub interface directly to create your pull request.","category":"page"},{"location":"","page":"ModuleMixins","title":"ModuleMixins","text":"CurrentModule = ModuleMixins","category":"page"},{"location":"#ModuleMixins","page":"ModuleMixins","title":"ModuleMixins","text":"","category":"section"},{"location":"","page":"ModuleMixins","title":"ModuleMixins","text":"Documentation for ModuleMixins.","category":"page"},{"location":"","page":"ModuleMixins","title":"ModuleMixins","text":"ModuleMixins is a way of composing families of struct definitions on a module level. Suppose we have several modules that contain structs of the same name. We can compose these modules such that all the structs they have in common are merged. Methods that work on one component should now work on the composed type.","category":"page"},{"location":"","page":"ModuleMixins","title":"ModuleMixins","text":"info: Info\nMost problems with object type abstraction can be solved in Julia by cleverly using abstract types and multiple dispatch. Use ModuleMixins only after you have convinced yourself you absolutely need it.","category":"page"},{"location":"#Contributors","page":"ModuleMixins","title":"Contributors","text":"","category":"section"},{"location":"","page":"ModuleMixins","title":"ModuleMixins","text":"<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->\n<!-- prettier-ignore-start -->\n<!-- markdownlint-disable -->\n\n<!-- markdownlint-restore -->\n<!-- prettier-ignore-end -->\n\n<!-- ALL-CONTRIBUTORS-LIST:END -->","category":"page"},{"location":"10-introduction/#Introduction","page":"Introduction","title":"Introduction","text":"","category":"section"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"using ModuleMixins\n\n@compose module A\n  struct S\n    a\n  end\nend\n\n@compose module B\n  @mixin A\n\n  struct S\n    b\n  end\nend\n\nfieldnames(B.S)","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"A struct within a composed module can be mutable and/or @kwdef, abstract base types are also forwarded. All using and const statements are forwarded to the derived module, so that field types still compile.","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"using ModuleMixins\n\n@compose module A\n  const V = Vector{Int}\n  struct S\n    a::V\n  end\nend\n\n@compose module B\n  @mixin A\nend\n\ntypeof(B.S([42]).a)","category":"page"},{"location":"10-introduction/#Diamond-pattern","page":"Introduction","title":"Diamond pattern","text":"","category":"section"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"The following pattern of multiple inheritence should work:","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"using ModuleMixins: @compose\n\n@compose module A\n    struct S a::Int end\nend\n\n@compose module B\n    @mixin A\n    struct S b::Int end\nend\n\n@compose module C\n    @mixin A\n    struct S c::Int end\nend\n\n@compose module D\n    @mixin B, C\n    struct S d::Int end\nend\n\nfieldnames(D.S)","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"The type D.S now has fields a, b, c and d.","category":"page"},{"location":"10-introduction/#Motivation-from-OOP","page":"Introduction","title":"Motivation from OOP","text":"","category":"section"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"Julia is not an object oriented programming (OOP) language. In general, when one speaks of object orientation a mix of a few related concepts is meant:","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"Compartimenting program state.\nMessage passing between entities.\nAbstraction over interfaces.\nInheritence or composition.","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"Where in other languages these concepts are mostly covered by classes, in Julia most of the patterns that are associated with OOP are implemented using multiple dispatch.","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"The single concept that is not covered by the Julia language or the standard library is inheritance or object composition. Suppose we have two types along with some methods (in the real world these would be much more extensive structs):","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"struct A\n    x::Int\nend\n\namsg(a::A) = \"Hello $(a.x)\"\n\nstruct B\n    y::Int\nend\n\nbmsg(b::B) = \"Goodbye $(b.y)\"","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"Now, for some reason you want to compose those types so that amsg and bmsg can be called on our new type.","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"struct C\n    x::Int\n    y::Int\nend\n\namsg(c::C) = amsg(A(c.x))\nbmsg(c::C) = bmsg(B(c.y))","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"There are some downsides to this: we needed to copy data from C into the more primitive types A and B. We could get around this by removing the types from the original method implementations. Too strict static typing can be a bad thing in Julia!","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"An alternative approach would be to define C differently:","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"struct C\n    a::A\n    b::B\nend","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"We would need to abstract over member access using getter and setter methods. When objects grow a bit larger, this type of compositon comes with a lot of boilerplate code. In Julia this is synonymous to: we need macros.","category":"page"},{"location":"10-introduction/","page":"Introduction","title":"Introduction","text":"There we have it: if we want any form of composition or inheritance in our types, we need macros to support us.","category":"page"},{"location":"20-example/#Example","page":"Example","title":"Example","text":"","category":"section"},{"location":"20-example/","page":"Example","title":"Example","text":"It cannot be helped that this example will seem a bit contrived.","category":"page"},{"location":"20-example/","page":"Example","title":"Example","text":"We're modelling the movement of a spring. It can be useful to put some common definitions in a separate module.","category":"page"},{"location":"20-example/","page":"Example","title":"Example","text":"#| file: examples/spring.jl\n\nusing ModuleMixins\nusing CairoMakie\nusing Unitful\n\nmodule Common\n    abstract type AbstractInput end\n    abstract type AbstractState end\n\n    function initial_state(input::AbstractInput)\n        error(\"Can't construct from AbstractInput\")\n    end\n\n    export AbstractInput, AbstractState, initial_state\nend\n\n<<example-time>>\n<<example-spring>>\n<<example-run>>","category":"page"},{"location":"20-example/","page":"Example","title":"Example","text":"The model has input parameters and a mutable state. We'll have a time component:","category":"page"},{"location":"20-example/","page":"Example","title":"Example","text":"#| id: example-time\n\n@compose module Time\n    using Unitful\n    using ..Common\n\n    @kwdef struct Input <: AbstractInput\n        t_step::typeof(1.0u\"s\")\n        t_end::typeof(1.0u\"s\")\n    end\n\n    mutable struct State <: AbstractState\n        time::typeof(1.0u\"s\")\n    end\n\n    function step!(input::AbstractInput, state::AbstractState)\n        state.time += input.t_step\n    end\n\n    function run(model, input::AbstractInput)\n        s = model.initial_state(input)\n        Channel() do ch\n            while s.time < input.t_end\n                model.step!(input, s)\n                put!(ch, deepcopy(s))\n            end\n        end\n    end\nend","category":"page"},{"location":"20-example/","page":"Example","title":"Example","text":"Note that the run function is generic. And a component for the spring.","category":"page"},{"location":"20-example/","page":"Example","title":"Example","text":"#| id: example-spring\n\n@compose module Spring\n    @mixin Time\n    using ..Common\n    using Unitful\n\n    @kwdef struct Input <: AbstractInput\n        spring_constant::typeof(1.0u\"s^-2\")\n        initial_position::typeof(1.0u\"m\")\n    end\n\n    mutable struct State <: AbstractState\n        position::typeof(1.0u\"m\")\n        velocity::typeof(1.0u\"m/s\")\n    end\n\n    function step!(input::AbstractInput, state::AbstractState)\n        delta_v = -input.spring_constant * state.position\n        state.position += state.velocity * input.t_step\n        state.velocity += delta_v * input.t_step\n    end\nend","category":"page"},{"location":"20-example/","page":"Example","title":"Example","text":"Now we may compose these using @mixin:","category":"page"},{"location":"20-example/","page":"Example","title":"Example","text":"#| id: example-run\n\n@compose module Model\n    @mixin Time, Spring\n    using ..Common\n    using Unitful\n\n    function step!(input::Input, state::State)\n        Spring.step!(input, state)\n        Time.step!(input, state)\n    end\n\n    function initial_state(input::Input)\n        return State(0.0u\"s\", input.initial_position, 0.0u\"m/s\")\n    end\nend","category":"page"},{"location":"20-example/","page":"Example","title":"Example","text":"And see the result.","category":"page"},{"location":"20-example/","page":"Example","title":"Example","text":"#| id: example-run\n\nfunction plot_result()\n    input = Model.Input(\n        t_step = 0.001u\"s\",\n        t_end = 1.0u\"s\",\n        spring_constant = 250.0u\"s^-2\",\n        initial_position = 1.0u\"m\",\n    )\n\n    output = Time.run(Model, input) |> collect\n    times = [f.time for f in output]\n    pos = [f.position for f in output]\n\n    fig = Figure()\n    ax = Axis(fig[1, 1])\n    lines!(ax, times, pos)\n    save(\"docs/src/fig/plot.svg\", fig)\nend\n\nplot_result()","category":"page"},{"location":"20-example/","page":"Example","title":"Example","text":"(Image: Example output)","category":"page"}]
}