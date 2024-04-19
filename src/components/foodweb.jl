# Foodweb aka. "Trophic layer",
# is special because it does structure the whole network
# in a way that makes it a dependency
# of numerous other biorates and interaction layers.
# Typically, many default values are calculated from this layer,
# and values checks are performed against this layer.

"""
The Foodweb component, aka. "Trophic layer",
adds a set of trophic links connecting species in the model.
This is one of the most structuring components.

# Blueprint Creation from Raw Links.

From an adjacency list:

```jldoctest
julia> fw = Foodweb([:a => :b, :b => [:c, :d]])
blueprint for Foodweb with 2 trophic links:
  A:
  :a eats :b
  :b eats :c and :d

julia> Model(fw) # Automatically brings a 'Species' component.
Model with 2 components:
  - Species: 4 (:a, :b, :c, :d)
  - Foodweb: 3 links

julia> Model(Foodweb([4 => [2, 1], 2 => 1])) #  From species indices.
Model with 2 components:
  - Species: 4 (:s1, :s2, :s3, :s4)
  - Foodweb: 3 links
```

From a matrix:

```jldoctest
julia> fw = Foodweb([0 0 1; 1 0 1; 0 0 0])
blueprint for Foodweb with 3 trophic links:
  A: 3×3 SparseArrays.SparseMatrixCSC{Bool, Int64} with 3 stored entries:
 ⋅  ⋅  1
 1  ⋅  1
 ⋅  ⋅

julia> Model(fw)
Model with 2 components:
  - Species: 3 (:s1, :s2, :s3)
  - Foodweb: 3 links
```

# Blueprint Creation from Random Models.

__Cascade__ model: specify the desired number of species `S` and connectance `C`.

```jldoctest
julia> using Random
       Random.seed!(12)
       fw = Foodweb(:cascade; S = 5, C = 0.2)
blueprint for Foodweb with 5 trophic links:
  A: 5×5 SparseArrays.SparseMatrixCSC{Bool, Int64} with 5 stored entries:
 ⋅  1  ⋅  1  1
 ⋅  ⋅  ⋅  ⋅  ⋅
 ⋅  ⋅  ⋅  1  ⋅
 ⋅  ⋅  ⋅  ⋅  1
 ⋅  ⋅  ⋅  ⋅  ⋅
```

Random foodwebs are drawn until the desired connectance is obtained,
within a tolerance level defaulted to `tol_C = 0.1 * C`,
modifiable as a keyword argument.

__Niche__ model: either specify the connectance `C` or number of links `L`.

```jldoctest
julia> fw = Foodweb(:niche; S = 5, C = 0.2) #  From connectance.
blueprint for Foodweb with 5 trophic links:
  A: 5×5 SparseArrays.SparseMatrixCSC{Bool, Int64} with 5 stored entries:
 ⋅  ⋅  ⋅  ⋅  ⋅
 ⋅  ⋅  ⋅  ⋅  ⋅
 1  1  ⋅  ⋅  ⋅
 ⋅  ⋅  1  ⋅  ⋅
 1  1  ⋅  ⋅  ⋅

julia> fw = Foodweb(:niche; S = 5, L = 4) #  From number of links.
blueprint for Foodweb with 4 trophic links:
  A: 5×5 SparseArrays.SparseMatrixCSC{Bool, Int64} with 4 stored entries:
 ⋅  ⋅  ⋅  ⋅  ⋅
 ⋅  ⋅  ⋅  ⋅  ⋅
 ⋅  ⋅  ⋅  ⋅  ⋅
 1  ⋅  ⋅  ⋅  ⋅
 1  1  1  ⋅  ⋅
```

The default tolerance levels for the niche model
are `tol_C = 0.1 * C` and `tol_L = 0.1 * L`,
modifiable as keyword arguments.

For either random model, the following keyword arguments can also be specified:

  - `reject_cycles = false` (default): raise to forbid trophic cycles.
  - `reject_if_disconnected = true` (default): lower to allow disconnected trophic networks.
  - `max_iterations = 10^5` (default): give up if no satisfying network can be found
    after this number of random trials.

# Properties.

A model `m` with a `Foodweb` has the following properties.

  - `m.A` or `m.trophic_links`: a view into the matrix of trophic links.
  - `m.n_trophic_links`: the number of trophic links in the model.
  - `m.trophic_levels`: calculate the trophic level of every species in the model.
  - Distinguishing between `producers` (species without outgoing trophic links)
    and `consumers` (species with outgoing trophic links):
      + `m.{producers,consumers}_mask`: a boolean vector to select either kind of species.
      + `m.n_{producers,consumers}`: count number of species of either kind.
      + `is_{producer,consumer}(m, i)`: check whether species `i` (name or index) is of either kind.
      + `m.{producers,consumer}_indices`: iterate over either species kind indices.
      + `m.{producers,consumer}_{sparse,dense}_index`: obtain a
        \$species\\_name \\mapsto species\\_index\$ mapping:
          * the `sparse` index yields indices valid within the whole collection of species.
          * the `dense` index yields indices only valid within the restricted collection
            of species of either kind.
  - Distinguishing between `preys` (species with incoming trophic links)
    and `tops` predators (species without incoming trophic links) works the same way.
  - `m.producers_links`: boolean matrix highlighting potential links between producers.
  - `m.herbivorous_links`: highlight only consumer-to-producer trophic links.
  - `m.carnivorous_links`: highlight only consumer-to-consumer trophic links.

```jldoctest
julia> m = Model(Foodweb([:a => :b, :b => [:c, :d], :d => :e]));

julia> m.n_trophic_links
4

julia> m.A
5×5 EcologicalNetworksDynamics.TrophicLinks:
 0  1  0  0  0
 0  0  1  1  0
 0  0  0  0  0
 0  0  0  0  1
 0  0  0  0  0

julia> m.trophic_levels
5-element EcologicalNetworksDynamics.TrophicLevels:
 3.5
 2.5
 1.0
 2.0
 1.0

julia> m.producers_mask
5-element EcologicalNetworksDynamics.ProducersMask:
 0
 0
 1
 0
 1

julia> m.preys_mask
5-element EcologicalNetworksDynamics.PreysMask:
 0
 1
 1
 1
 1

julia> m.n_producers, m.n_consumers
(2, 3)

julia> m.n_tops, m.n_preys
(1, 4)

julia> is_top(m, 1), is_top(m, 2)
(true, false)

julia> collect(m.consumers_indices)
3-element Vector{Int64}:
 1
 2
 4

julia> m.producers_sparse_index
OrderedCollections.OrderedDict{Symbol, Int64} with 2 entries:
  :c => 3
  :e => 5

julia> m.producers_dense_index
OrderedCollections.OrderedDict{Symbol, Int64} with 2 entries:
  :c => 1
  :e => 2

julia> m.producers_links
5×5 EcologicalNetworksDynamics.ProducersLinks:
 0  0  0  0  0
 0  0  0  0  0
 0  0  1  0  1
 0  0  0  0  0
 0  0  1  0  1

julia> m.herbivorous_links
5×5 EcologicalNetworksDynamics.HerbivorousLinks:
 0  0  0  0  0
 0  0  1  0  0
 0  0  0  0  0
 0  0  0  0  1
 0  0  0  0  0

julia> m.carnivorous_links
5×5 EcologicalNetworksDynamics.CarnivorousLinks:
 0  1  0  0  0
 0  0  0  1  0
 0  0  0  0  0
 0  0  0  0  0
 0  0  0  0  0
```
"""
mutable struct Foodweb <: ModelBlueprint
    A::@GraphData {SparseMatrix, Adjacency}{:bin}

    # Specify edges by hand.
    Foodweb(A) = new(@tographdata A EA{:bin})

    # Or draw them at random.
    # These models typically require a value for S,
    # which will be used to imply the number of species
    # if the species component is automatically added,
    # but which must *match* it if already present.
    # There is no way to avoid this possible repetition of S
    # without allowing stochastic / fallible component expansion.
    # Fortunately, most users will just imply the species compartment
    # from the foodweb itself.
    # TODO: stochastic expansion *could* actually happen during early check,
    # so that failures would be okay,
    # and the behaviour would match the behaviour of non-trophic layers.
    # This would result in other blueprints needing to be defined for the foodweb component
    # like FoodwebFromNiche and FoodwebFromCascade.
    # Wait on framework refactoring to improve semantics and ergonomics first?
    function Foodweb(model::Union{Symbol,AbstractString}; kwargs...)
        model = @tographdata model Y{}

        @kwargs_helpers kwargs

        given(:S) || argerr("Random foodweb models requires a number of species 'S'.")
        S = take!(:S)

        # Default values.
        rc = take_or!(:reject_cycles, false)
        rd = take_or!(:reject_if_disconnected, true)
        max = take_or!(:max_iterations, 10^5)

        @expand_if_symbol(
            model,

            # The niche model is either parametrized with C or L.
            :niche => begin

                (given(:C) || given(:L)) ||
                    argerr("The niche model requires either a connectance value 'C' \
                            or a number of links 'L'.")

                (given(:C) && given(:L)) &&
                    argerr("Cannot provide both a connectance 'C' \
                            and a number of links 'L'.")

                if given(:C)

                    C = take!(:C, Float64)
                    tol = take_or!(:tol_C, 0.1 * C)
                    no_unused_arguments()

                    #! format: off
                    Internals.model_foodweb_from_C(
                        Internals.niche_model,
                        S, C, nothing, # old 'p_forbidden' ?
                        tol, rc, rd, max,
                    )
                    #! format: on
                else

                    L = take!(:L, Int64)
                    tol = take_or!(:tol_L, round(Int64, 0.1 * L))
                    no_unused_arguments()

                    #! format: off
                    Internals.model_foodweb_from_L(
                        Internals.niche_model,
                        S, L, nothing, # old 'p_forbidden' ?
                        tol, rc, rd, max,
                    )
                    #! format: on
                end
            end,

            # The cascade model is only parametrized from C.
            :cascade => begin

                given(:C) || argerr("The cascade model requires a connectance value 'C'.")

                C = take!(:C)
                tol = take_or!(:tol_C, 0.1 * C)
                no_unused_arguments()

                #! format: off
                Internals.model_foodweb_from_C(
                    Internals.cascade_model,
                    S, C, nothing, # old 'p_forbidden' ?
                    tol, rc, rd, max,
                )
                #! format: on
            end
        )
        new(sparse(model))
    end
end

function F.early_check(_, bp::Foodweb)
    (; A) = bp
    if A isa AbstractMatrix
        n, m = size(A)
        n == m || checkfails("The adjacency matrix of size $((m, n)) is not squared.")
    end
end

# If needed, infer the number of species from adjacency data.
function Species(bp::Foodweb)
    (; A) = bp
    if A isa AbstractMatrix
        S = size(A, 1)
        Species(S)
    elseif A isa BinAdjacency{Int64}
        S = refspace(A)
        Species(S)
    elseif A isa BinAdjacency{Symbol}
        names = refs(A)
        Species(names)
    end
end

function F.check(m, bp::Foodweb)
    (; A) = bp
    (; S) = m
    index = m._foodweb._species_index
    @check_size_if_matrix A (S, S)
    @check_refs_if_list A :species index
end

function F.expand!(m, bp::Foodweb)
    (; A) = bp
    index = m._foodweb._species_index

    @to_sparse_matrix_if_adjacency A index index

    # Internal network is guaranteed to be an 'Internals.FoodWeb'
    # because NTI components cannot be set before 'Foodweb' component.
    fw = m.network
    fw.A = A
    fw.method = "from component" # (internals legacy)

    # Add trophic edges to the topology.
    top = m._topology
    add_edge_type!(top, :trophic)
    add_edges_within_node_type!(top, :species, :trophic, A)

    # TODO: this should happen with components-combinations-triggered-hooks
    # (see Nutrient.Nodes expansion)
    Topologies.has_node_type(top, :nutrients) && Nutrients.connect_producers_to_nutrients(m)

end

@component Foodweb implies(Species)
export Foodweb

# Consistency alias.
const TrophicLayer = Foodweb
export TrophicLayer

# ==========================================================================================
# Foodweb queries.

# Topology as a matrix.
@expose_data edges begin
    property(trophic_links, A)
    get(TrophicLinks{Bool}, sparse, "trophic link")
    ref(m -> m._foodweb.A)
    @species_index
    depends(Foodweb)
end

# Number of links.
@expose_data graph begin
    property(n_trophic_links)
    ref_cache(m -> sum(m._trophic_links))
    get(m -> m._n_trophic_links)
    depends(Foodweb)
end

# Trophic levels.
@expose_data nodes begin
    property(trophic_levels)
    get(TrophicLevels{Float64}, "species")
    ref_cache(m -> Internals.trophic_levels(m._trophic_links))
    @species_index
    depends(Foodweb)
end

# More elaborate queries.
# TODO: abstract over the following to reduce boilerplate.
# as it all just stems from sparse boolean node information.
include("./producers-consumers.jl")
include("./preys-tops.jl")

#-------------------------------------------------------------------------------------------
# Get a sparse matrix highlighting only the producer-to-producer links.

function calculate_producers_links(model)
    (; S) = model
    prods = model.producers_indices
    res = spzeros(Bool, S, S)
    for i in prods, j in prods
        res[i, j] = true
    end
    res
end

@expose_data edges begin
    property(producers_links)
    get(ProducersLinks{Bool}, sparse, "producer link")
    ref_cache(calculate_producers_links)
    @species_index
    depends(Foodweb)
end

#-------------------------------------------------------------------------------------------
# Get a sparse matrix highlighting only 'herbivorous' trophic links: consumers-to-producers.
#                                    or 'carnivorous' trophic links: consumers-to-consumers.

function calculate_herbivorous_links(model)
    (; S, _trophic_links) = model
    res = spzeros(Bool, S, S)
    preds, preys, _ = findnz(_trophic_links)
    for (pred, prey) in zip(preds, preys)
        is_producer(model, prey) && (res[pred, prey] = true)
    end
    res
end

function calculate_carnivorous_links(model)
    (; S, _trophic_links) = model
    res = spzeros(Bool, S, S)
    preds, preys, _ = findnz(_trophic_links)
    for (pred, prey) in zip(preds, preys)
        is_consumer(model, prey) && (res[pred, prey] = true)
    end
    res
end

@expose_data edges begin
    property(herbivorous_links)
    get(HerbivorousLinks{Bool}, sparse, "herbivorous link")
    ref_cache(calculate_herbivorous_links)
    @species_index
    depends(Foodweb)
end

@expose_data edges begin
    property(carnivorous_links)
    get(CarnivorousLinks{Bool}, sparse, "carnivorous link")
    ref_cache(calculate_carnivorous_links)
    @species_index
    depends(Foodweb)
end

# ==========================================================================================
# Display.

# Blueprint.
function Base.show(io::IO, fw::Foodweb)
    (; A) = fw
    L = if A isa AbstractMatrix
        sum(A)
    else
        sum(length.(values(A)))
    end
    print(io, "blueprint for Foodweb with $L trophic link$(L == 1 ? "" : "s")")
end

function Base.show(io::IO, ::MIME"text/plain", fw::Foodweb)
    (; A) = fw
    print(io, "$fw:\n  A:")
    if A isa AbstractMatrix
        println(io, " " * repr(MIME("text/plain"), A))
    else
        for (pred, preys) in A
            preys =
                isempty(preys) ? "nothing" : join((repr(p) for p in preys), ", ", " and ")
            print(io, "\n  $(repr(pred)) eats $preys")
        end
    end
end

# Component.
function F.display(model, fw::Type{Foodweb})
    n = model.n_trophic_links
    "Foodweb: $n link$(n > 1 ? "s" : "")"
end
