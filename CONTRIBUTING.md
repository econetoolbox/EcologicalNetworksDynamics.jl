# Contribution guidelines

You are willing to contribute to `EcologicalNetworksDynamics.jl`
and edit the source code. Thank you ♡.
This guide is supposed to help you
through the installation process
as a developer instead of a user,
and introduce a typical developing workflow
so you can be comfortable contributing.

This guide assumes you're working on a standard linux distribution,
as it uses basic shell commands and [Julia's REPL].
If you are not and you have trouble following along,
don't hesitate to reach out at
[econetoolbox/EcologicalNetworksDynamics.jl]
and ask for support.

[econetoolbox/EcologicalNetworksDynamics.jl]: https://github.com/econetoolbox/EcologicalNetworksDynamics.jl
[Julia's REPL]: https://docs.julialang.org/en/v1/stdlib/REPL/

## Set up a clean working directory to host the project

The package sources
are essentially contained within one directory
hereafter named `./EcologicalNetworksDynamics.jl/` or "source directory".
In this directory, you can freely
__(1)__ __navigate and edit to contribute__.
Once you are done,
you will likely want to
__(2)__ __try your modifications__
with some personal examples and toy scripts.
This is how you can decide that you are happy with your contribution.

Regarding __(2)__,
we advise against working directly in the source directory.
Instead, use another directory like `EcoNetD-sandbox/` or `EcoNetD-dev/`.
This gives you full latitude to use custom IDE configurations there,
generate figures *etc.* without polluting the sources.

### 1. Create your development directory

Make yourself at home with:

```console
$ mkdir EcoNetD-dev
$ cd EcoNetD-dev
```

### 2. Clone EcologicalNetworksDynamics sources

Download latest state of the project with:

```console
$ git clone git@github.com:econetoolbox/EcologicalNetworksDynamics.jl
```

At this point, your directories structure should look something like:

```
EcoNetD-dev/
├── EcologicalNetworksDynamics/
│   ├── .git/
│   ├── README.md
│   ├── CONTRIBUTING.md
│   ├── Project.toml
│   ├── ...
```

### 3. Setting up your development environment

Julia works with distinct [environments].
Any directory can become a Julia environment
provided it contains correct `Project.toml` and `Manifest.toml` files.

[environments]: https://pkgdocs.julialang.org/v1/environments/

Now you want to add the package to your development environment.
Enter Julia REPL first with:

```sh
$ julia --project=. # Assuming '.' refers to your development directory.
```

Then, from the REPL:

```julia
julia> ]                      # Just type ']' key at the prompt.
(EcoNetD-dev) pkg> dev ./EcologicalNetworksDynamics.jl # "Dev-dependency".
(EcoNetD-dev) pkg> add Revise  # Track sources modifications.
(EcoNetD-dev) pkg> instantiate # This may take a while the first time.
```

[`Revise`] is very useful to not
to have to restart your development session
and reload `./EcologicalNetworksDynamics.jl` code
after every modification.

[`Revise`]: https://timholy.github.io/Revise.jl/stable/

At this point, you should be able to use the package from this environment.
To verify, create the following toy script:

```
EcoNetD-dev/
├── sandbox.jl     <- "toy script"
├── Project.toml   <- (automatically created during `dev` and `add` commands)
├── Manifest.toml  <- (automatically created during `instantiate` command)
├── EcologicalNetworksDynamics.jl/
│   ├── ...
```

In `sandbox.jl`:
```julia
using Revise
using EcologicalNetworksDynamics

# Dummy use of the package just to try it out.
foodweb = Foodweb([:a => :b])

println("Good.")
```

If you can successfully run it with:

```console
$ julia --project=. sandbox.jl
```

Then your initial setup is successful.

The above line may take a long time run,
because the first few lines are typically slow in Julia.
In your actual workflow,
we recommend that you keep a julia REPL open instead:

```console
$ julia --project=. # Open a repl.
julia> using Revise
julia> using EcologicalNetworksDynamics
julia> # Pass your sandbox script lines here.
julia> # Only close this REPL if necessary: it will take time to start again.
```

### 4. Setup/Refresh EcologicalNetworksDynamics source directory

At this point,
you can use and modify the package,
but you cannot generate documentation,
run the tests or the benchmarks yet.

This section explains
how to correctly set up the source `./EcologicalNetworksDynamics.jl/` directory.
It is also useful if you feel like you have messed everything up
and you wish to reset this directory to a clean state.

#### Clean up whole sources directory

The following needs to happen
at the root source directory `./EcologicalNetworksDynamics.jl`:

```console
$ cd path/to/EcologicalNetworksDynamics.jl/
```

Delete every file not tracked by git.
Beware that this will permanently delete any file not yet committed.

```console
$ git reset --hard  # Permanently erase all non-commited project modifications.
$ git checkout dev  # (or any branch you are willing to work on)
$ git clean -xdf    # Delete all non-tracked files.
```

#### Run the tests

You have modified existing functions
and you wish to ensure that you have not broken anything.
Alternately, you have written new functions
and added new tests to `./EcologicalNetworksDynamics.jl/test`
or in doctests strings.
In any case, you can run all tests with:

```console
$ cd path/to/EcologicalNetworksDynamics.jl
$ julia --project=.
julia> ]
(EcologicalNetworksDynamics) pkg> test  # Tests do take a while to run.
```

#### Generate documentation

You need to read the latest source documentation on current branch,
or you have written new docstrings,
documentation pages in `./EcologicalNetworksDynamics.jl/docs/src/`
and you would like to check what they look like.
Generate all documentation with:

```console
$ cd path/to/EcologicalNetworksDynamics.jl/docs
$ julia --project=. make.jl   # (fails if doctests fail)
```

Documentation is generated in `./EcologicalNetworksDynamics.jl/docs/build/`.
Browse with any web browser.
For instance:

```console
$ firefox ./build/index.html
```

## Work with git

### Basic workflow

Before working on your contribution,
make sure you do so on a dedicated branch,
for instance with:

```console
$ git checkout dev                 # Most common branch to base your work upon.
$ git checkout -b my_cool_feature  # Create your branch and switch to it.
```

Construct your successive commits as usual with.

```console
$ git add modified_or_new_files
$ git commit
```

When your feature is ready,
open a pull request with your branch on the official repo.
Your code will be reviewed there before it is eventually merged into `dev`.


### Keep your work downstream the `dev` branch

The project enforces linear git history with a *rebase* strategy.
As a consequence, as you are working on your branch,
it sometimes happens that `dev` moves forward in another direction.
This is not a problem and you can keep going until your pull request is ready.

If, however,
you need to integrate the latest `dev` features into your branch,
please *refrain* from introducing merge commits with commands like:

```console
$ # git merge dev  # This complicates enforcement of git rebase strategy!
```

Instead, rebase your branch onto the new `dev` location with commands like:
```console
$ git rebase dev  # You will be prompted for any conflict resolution then.
```
or, more explicitly:
```console
$ git rebase --onto dev my_cool_feature
```

Should you wish not to loose your original history before rebasing your branch,
you can create personal tags prior to rebase, for instance with:
```console
$ git tag -a my_safety_tag -m "The commit I was standing on before I rebased."
```

To check that everything went well, use either
```console
$ git log --decorate --oneline --graph --all --color
```
or your prefered git client / software / IDE extension.

Once it has been correctly rebased,
it is okay to submit by force-pushing *your branch* (not `dev`)
to the main repo:
```console
$ git push --force origin my_cool_feature
```

__In case you need any sort of kind help or support.
Don't hesitate to reach out to [econetoolbox/EcologicalNetworksDynamics.jl]__
__Happy contributing <3__
