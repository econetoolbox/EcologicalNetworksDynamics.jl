# Species nodes are the first basic type of node in the ecological graph model.

# (reassure JuliaLS)
(false) && (local Species, _Species)

# Typical, vanilla class component.
@class_component species Species species Species s
export Species

# Extra aliases used by the community.
@alias species.number S
@alias S richness
@alias S species.richness

@doc """
The Species component adds the most basic nodes compartment into the model: species.
There is one node per species, and every species is given a unique name and index.
The species ordering specified in this compartment is the reference species ordering.

```jldoctest
julia> sp = Species([:hen, :fox, :snake])
blueprint for Species:
  names: 3-element Vector{Symbol}:
 :hen
 :fox
 :snake

julia> m = Model(sp)
Model with 1 component:
  - Species: 3 (:hen, :fox, :snake)

julia> Model(Species(5)) # Default names generated.
Model with 1 component:
  - Species: 5 (:s1, :s2, :s3, :s4, :s5)
```

Typically, the species component is implicitly brought by other blueprints.

```jldoctest
julia> Model(Foodweb([:a => :b]))
Model with 2 components:
  - Species: 2 (:a, :b)
  - Foodweb: 1 link

julia> Model(BodyMass([4, 5, 6]))
Model with 2 components:
  - Species: 3 (:s1, :s2, :s3)
  - Body masses: [4.0, 5.0, 6.0]
```

The species component makes the following properties available to a model `m`:

  - `m.S` or `m.richness` or `m.species_richness` or `m.n_species`:
    number of species in the model.
  - `m.species_names`: list of species name in reference order.
  - `m.species_index`: get a \$species\\_name \\mapsto species\\_index\$ mapping.

```jldoctest
julia> (m.S, m.richness, m.species_richness, m.n_species) # All aliases for the same thing.
(3, 3, 3, 3)

julia> m.species_names
3-element EcologicalNetworksDynamics.SpeciesNames:
 :hen
 :fox
 :snake

julia> m.species_index
OrderedCollections.OrderedDict{Symbol, Int64} with 3 entries:
  :hen   => 1
  :fox   => 2
  :snake => 3
```
""" Species
