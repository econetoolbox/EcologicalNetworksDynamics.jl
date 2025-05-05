Here is how `EcologicalNetworksDynamics.jl` handles
dependencies, stability, compatibility and reproducibility.

### Dependencies.

Dependencies are listed under the `[deps]` section of the main `Project.toml`.
In particular, there is a list of `[extras]` dependencies
only used for testing.
This is because the [alternative option][test/Project.toml]
is documented to be underspecified.

Sub-modules within `src/` all share the same dependencies.
Sub-environments like `docs/` and `use_cases/`
have their own `Project.toml` and need to be (manually) recorded
as package consumers by (manually) issuing:
```
$ julia --project=docs/ # (or use_cases/)
] dev .
```
The `test/` environment is special-cased by `Pkg.jl`.
Maybe this can all be made easier / more consistent
with the new [`[workspace]`][workspace] feature,
but it is still unclear to me ([@iago-lito])
whether this is sufficiently documented / specified / ironed out
to fit the concerns listed here.


### Stability

The package aims to follows [Julia's versionning rules][semver.jl].

Every exposed / documented part of the API
should be tested under `test/user/`.
As a consequence, what we consider "breaking" is
__any change to the observable behaviour tested under `test/user/`__,
except for:
- *Compilation/execution time*.
- *Floating-point numerical precision*:
  you should not expect numerical results of simulation to remain the same
  accross minor versions of the packages,
  even accross machines,
  or even accross runs.
- *Random draws*: you can expect seeded random operations to remain the same
  accross machines and runs, but not accross minor versions.
- *Console output*: you should not expect exact console display, for
  models, components, error messages, warning, information, logging *etc.*
  to remain stable accross minor versions.
  This includes wording, spacing, coloring, eliding, numbers precision, *etc.*

Note that this also excludes:
- Versions of re-exported external identifiers
  like `Solution` from `DifferentialEquations.jl`.
  `EcologicalNetworksDynamics.jl` is considered a wrapper
  around `DifferentialEquations.jl`.
  If you need to bump `DifferentialEquations.jl`
  for `EcologicalNetworksDynamics.jl` to work,
  we do not consider this a breaking change
  as long as the code under `test/user/` is not broken.
- Dependencies versions.
  We will try to maintain compatibility with the lowest possible versions
  of our dependencies for as long as possible.
  But if you have to upgrade your dependencies
  to make `EcologicalNetworksDynamics.jl` work,
  we do not consider it a breaking change
  as long as the code under `test/user/` is not broken.

### Compatibility

HERE: write and setup CI
- `to_lower.jl` to check lower bounds.
- `CompatHelperLocal` to check upper bounds.

### Reproducibility

- `to_pinned` to check against pinned environments.

[test/Project.toml]: https://pkgdocs.julialang.org/v1/creating-packages/#Alternative-approach:-test/Project.toml-file-test-specific-dependencies
[workspace]: https://pkgdocs.julialang.org/dev/toml-files/#The-%5Bworkspace%5D-section
[@iago-lito]: https://isem-evolution.fr/en/membre/bonnici/
[semver.jl]: https://pkgdocs.julialang.org/v1/compatibility/#Version-specifier-format
