# Version 0.2.1

## Breaking changes

- Components and blueprints are now two separate type hierachies.
- Components are singletons types
  whose fields are blueprint types expanding into themselves.
- Components can be directly called
  to transfer input to correct blueprint constructors
- Blueprints typically have different types based on their inputs.

  ```julia-repl
  julia> Species
  Species (component for <internals>, expandable from:
    Names: raw species names,
    Number: number of species,
  )
  julia> Species(5) isa Species.Number
  true
  julia> Species(["a", "b", "c"]) isa Species.Names
  true
  ```

  This comes with minor incompatible changes
  to the available set of blueprint constructor methods.
  For instance the redundant form
  `BodyMass(M = [1, 2])` is not supported anymore,
  but `BodyMass([1, 2])` does the same
  and `BodyMass(Z = 1.5)` still works as expected.

- Model properties are now typically namespaced to ease future extensions.
- Equivalent `get_*` and `set_*!` methods may still exist
  but they are no longer exposed or recommended:
  use direct property accesses instead.
  ```julia-repl
  julia> m = Model(Species(3))
  julia> m.species.number # (no more `.n_species` or `get_n_species(m)`)
  3
  julia> m.species.names == [:s1, :s2, :s3]
  true
  ```

- Some property names have changed. The following list is not exhaustive,
  but new names can easily be discovered using REPL autocompletion
  or the `properties(m)` and `properties(m.prop)` methods:
  - `model.trophic_links` becomes `model.trophic.matrix`,
    because it does yield a matrix and not some collection of "links".
    The alias `model.A` is still available.
  - Likewise,
    `model.herbivorous_links` becomes `model.trophic.herbivory_matrix` *etc.*
  - Akward plurals like `model.body_masses` and `model.metabolic_classes`
    become `model.body_mass` and `model.metabolic_class`.


## New features

- Model properties available with `<tab>`-completion within the REPL.

- Every blueprint *brought* by another is available as a brought field
  to be either *embedded*, *implied* or *unbrought*:
  ```julia-repl
  julia> fw = Foodweb.Matrix([0 0; 1 0]) # Implied (brought if missing).
  blueprint for <Foodweb>: Matrix {
    A: 1 trophic link,
    species: <implied blueprint for <Species>>,
  }
  julia> fw.species = [:a, :b]; # Embedded (brought, erroring if already present).
         fw
  blueprint for <Foodweb>: Matrix {
    A: 1 trophic link,
    species: <embedded blueprint for <Species>: Names {
      names: [:a, :b],
    }>,
  }
  julia> fw.species = nothing; # Unbrought (error if missing).
         fw
  blueprint for <Foodweb>: Matrix {
    A: 1 trophic link,
    species: <no blueprint brought>,
  }
  ```

- Every "leaf" "geometrical" model property *i.e.* a property whose futher
  model topology does not depend on or is not planned to depend on
  is now writeable.
  ```julia-repl
  julia> m = Model(fw, BodyMass(2));
         m.M[1] *= 10;
         m.M == [20, 2]
  true
  ```

- Values are checked prior to expansion:
  ```julia-repl
  julia> m = Model(fw, Efficiency(1.5))
  ERROR: Blueprint value cannot be expanded:
    Not a value within [0, 1]: e = 1.5.
  ```

- Efficiency from a matrix implies a Foodweb.
  ```julia-repl
  julia> e = 0.5;
         m = Model(Efficiency([
            0 e e
            0 0 e
            e 0 0
         ]));
         has_component(m, Foodweb)
  true
  julia> m.A
  3×3 EcologicalNetworksDynamics.TrophicMatrix:
   0  1  1
   0  0  1
   1  0  0
  ```

- Aggregated blueprints expansion is clever enough
  to not error if two brought blueprints would bring the same component:
  ```julia-repl
  julia> base = Model(
             Foodweb([:a => :b]),
             BodyMass(1),
             MetabolicClass(:all_invertebrates),
         )
         ni = NutrientIntake(nodes = 2; supply = [1, 2], turnover = [1, 2]);
         # 3 different specifications of Nutrients.Nodes.
  julia> ni.nodes
  <embedded blueprint for <Nutrients.Nodes>: Number {
    n: 2,
  }>
  julia> ni.supply.nutrients
  <implied blueprint for <Nutrients.Nodes>>
  julia> ni.turnover.nutrients
  <implied blueprint for <Nutrients.Nodes>>
  julia> base + ni; # But this still works fine.
  ```

- Aggregated blueprints expansion is clever enough
  to correctly figure a correct expansion order among brought blueprints:
  ```julia-repl
  julia> ni = NutrientIntake(; turnover = [1, 2]);
  julia> base + ni; # `ni.turnover.nutrients` is expanded before `ni.supply`.
  ```
