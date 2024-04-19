# Species nodes are the first basic type of node in the ecological graph model.
# On component expansion, they are given an index and a name,
# which cannot be changed later, or the number of species,
# because too many things depend on these.

"""
The Species component adds the most basic nodes compartment into the model: species.
There is one node per species, and every species is given a unique name and index.
The species ordering specified in this compartment is the reference species ordering.

```jldoctest
julia> sp = Species(["hen", "fox", "snake"])
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
"""
mutable struct Species <: ModelBlueprint
    names::Vector{Symbol}
    # Generate dummy names if not provided.
    # Don't own data if useful to user.
    Species(names) = new(Symbol.(names))
    Species(n::Integer) = new([Symbol(:s, i) for i in 1:n])
    Species(names::Vector{Symbol}) = new(names)
end

function F.check(model, bp::Species)
    (; names) = bp
    # Forbid duplicates (triangular check).
    for (i, a) in enumerate(names)
        for j in (i+1):length(names)
            b = names[j]
            a == b && checkfails("Species $i and $j are both named $(repr(a)).")
        end
    end
end

function F.expand!(model, bp::Species)
    # Species are still internally stored within a value named "Foodweb",
    # but this will be refactored.
    fw = Internals.FoodWeb(bp.names)
    model.network = fw
    add_nodes!(model._topology, bp.names, :species)
    # Keep reference safe in case we later switch to a multiplex network,
    # and want to add the layers one by one.
    model._foodweb = fw
end

@component Species
export Species

# ==========================================================================================
# Basic queries

# Number of species aka. "richness".
@expose_data graph begin
    property(richness, species_richness, n_species, S)
    get(m -> length(m._species_index))
    depends(Species)
end

# View into species names.
@expose_data nodes begin
    property(species_names)
    get(SpeciesNames{Symbol}, "species")
    # Need to convert from internal legacy strings.
    ref_cache(m -> Symbol.(m._foodweb.species))
    depends(Species)
end

# Get (ordered) species index.
@expose_data graph begin
    property(species_index)
    ref_cache(m -> OrderedDict(name => i for (i, name) in enumerate(m._species_names)))
    get(m -> deepcopy(m._species_index))
    depends(Species)
end

# Get a closure able to convert species indices into the corresponding labels
# defined within the model.
@expose_data graph begin
    property(species_label)
    ref_cache(
        m ->
            (i) -> begin
                names = m._species_names
                n = length(names)
                if 1 <= i <= length(names)
                    names[i]
                else
                    (are, s) = n > 1 ? ("are", "s") : ("is", "")
                    argerr("Invalid index ($(i)) when there $are $n species name$s.")
                end
            end,
    )
    # This technically leaks a reference to the inner model as `m.species_label.m`,
    # but closure captures being accessible as fields is an implementation detail
    # and no one should rely on it.
    get(m -> m._species_label)
    depends(Species)
end

# ==========================================================================================
# Numerous views into species nodes will make use of this index.
macro species_index()
    esc(:(index(m -> m._species_index)))
end

# ==========================================================================================
# Display.

function F.display(model, ::Type{Species})
    (; S) = model
    names = model.species_names
    "Species: $S ($(join_elided(names, ", ")))"
end
