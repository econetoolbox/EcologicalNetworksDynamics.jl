# v0.x.0

- Producers competition links are reified as edges.
  - Breaking (minor): `producers.competition`
    is now split into `.matrix` and `.mask`.
  - Breaking (minor): producers competition rates
    cannot be modified anymore outside the edges mask.

- Improved display for sparse graph data views.

- Fix topology bug: isolated producers with selfing edges are still isolated.

# v0.3.0 Upgrade Blueprint/Components Framework

## Breaking changes (minor)

- Components and blueprints are now two separate type hierachies.
  ```julia-repl
  julia> Foodweb # The component.
  Foodweb (component for <internals>, expandable from:
    Matrix: boolean matrix of trophic links,
    Adjacency: adjacency list of trophic links,
  )
  julia> typeof(Foodweb)
  <Foodweb> (component type EcologicalNetworksDynamics._Foodweb)

  julia> fw = Foodweb.Adjacency([:a => :b]) # A blueprint for this component.
  blueprint for <Foodweb>: Adjacency {
    A: {a: {b}},
    species: <implied blueprint for <Species>>,
  }
  julia> typeof(fw)
  Foodweb_.Adjacency (blueprint type for System{<internals>})
  julia> fw isa Foodweb
  false
  julia> fw isa Foodweb.Adjacency
  true
  ```

- Components are singletons types
  whose fields are blueprint types expanding into themselves.
  ```julia
  Species        # The component.
  Species.Names  # A blueprint to expand from a list of names.
  Species.Number # A blueprint to expand from a species count.
  ```

- Components can be directly called
  to transfer input to correct blueprint constructors
  ```julia-repl
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
  Equivalent `get_*` and `set_*!` methods may still exist
  but they are no longer exposed or recommended:
  use direct property accesses instead.
  ```julia-repl
  julia> m = Model(Foodweb([:a => [:b, :c]]));
  julia> m.species # The namespace.
  Property space for '<internals>': .species
    .index
    .richness
    .label
    .names
    .number
  julia> m.species.number # (no more `m.n_species` or `get_n_species(m)`)
  3

  julia> m.trophic # Another namespace.
  Property space for '<internals>': .trophic
    .levels
    .n_links
    .matrix
    .herbivory_matrix
    .carnivory_matrix
    .A
  julia> m.trophic.matrix
  3×3 EcologicalNetworksDynamics.TrophicMatrix:
   0  1  1
   0  0  0
   0  0  0
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

- Julia allows linear indexing into 2D structures,
  but the package chooses instead to consider this a semantic flaw:
  ```julia-repl
  julia> m = Model(
             Foodweb([:a => [:b, :c], :b => [:c, :d]]),
             Efficiency(:Miele2019; e_herbivorous = .1, e_carnivorous = .2),
         );
         m.e[5]
  ERROR: View error (EcologicalNetworksDynamics.EfficiencyRates):
  Edges data are 2-dimensional:
  cannot access trophic link data values with 1 index: [5].
  ```

## New features

- Colored console display.
  ```julia-repl
  julia> NutrientIntake() # (won't work in a .md file: try in your REPL)
  blueprint for <NutrientIntake>: NutrientIntake_ {
    r: <embedded blueprint for <GrowthRate>: Allometric {
      allometry: Allometry(p: (a: 1.0, b: -0.25), i: (), e: ()),
    }>,
    nodes: <embedded blueprint for <Nodes>: PerProducer {
      n: 1,
    }>,
    turnover: <embedded blueprint for <Turnover>: Flat {
      t: 0.25,
    }>,
    supply: <embedded blueprint for <Supply>: Flat {
      s: 4.0,
    }>,
    concentration: <embedded blueprint for <Concentration>: Flat {
      c: 0.5,
    }>,
    half_saturation: <embedded blueprint for <HalfSaturation>: Flat {
      h: 0.15,
    }>,
  }
  ```

- Model properties available with `<tab>`-completion within the REPL.
  ```julia-repl
  julia> m = Model(Foodweb([:a => [:b, :c]]));
  julia> m.trop|<tab> # -> m.trophic|
  julia> m.trophic.|<tab>
  A                 carnivory_matrix
  herbivory_matrix  levels
  matrix            n_links
  ```

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

- Aggregated blueprints expansion is now clever enough
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

- Aggregated blueprints expansion is now clever enough
  to correctly figure a correct expansion order among brought blueprints:
  ```julia-repl
  julia> ni = NutrientIntake(; turnover = [1, 2]);
  julia> base + ni; # `ni.turnover.nutrients` is expanded before `ni.supply`.
  ```
# v0.2.1

🚨 Quick patch to fix [#171]:
- Bump requirement from `DiffEqCallbacks v3.4` to `v4.0`.
- Fix a few tests broken under Julia 11.

[#171]: https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/issues/171

# v0.2.0 First Release

Introduce `EcologicalNetworksDynamics.jl`, '
improving over previous code known as `BEFWM.jl`, '
then polished from `BEFWM2.jl`.

No particular notes: [documentation] constitutes the starting point: welcome :)

We are very excited and happy to release.
It has been a pleasant work so far, and there is stil much to come. Enjoy!

[documentation]: https://beckslab.github.io/EcologicalNetworksDynamics.jl/
