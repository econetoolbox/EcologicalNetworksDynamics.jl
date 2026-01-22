# Foodweb aka. "Trophic layer",
# is special because it structures the whole network
# in a way that makes it a dependency
# of numerous other biorates and interaction layers.
# Typically, many default values are calculated from this layer,
# and values checks are performed against this layer.

# (reassure JuliaLS)
(false) && (local Foodweb, _Foodweb)

# ==========================================================================================
# Blueprints.

module Foodweb_
include("blueprint_imports.jl")
include("modules_identifiers.jl")
import .EN: _Species, Species

#-------------------------------------------------------------------------------------------
# From matrix.

mutable struct Matrix <: Blueprint
    A::@GraphData SparseMatrix{:bin}
    species::Brought(Species)
    Matrix(A, sp = Species) = new(@tographdata(A, SparseMatrix{:bin}), sp)
end
# Infer number of species from matrix size.
F.implied_blueprint_for(bp::Matrix, ::_Species) = Species(size(bp.A, 1))
@blueprint Matrix "boolean matrix of trophic links"
export Matrix

function F.early_check(bp::Matrix)
    (; A) = bp
    n, m = size(A)
    n == m || checkfails("The adjacency matrix of size $((m, n)) is not squared.")
end

function F.late_check(raw, bp::Matrix)
    (; A) = bp
    S = @get raw.S
    @check_size A (S, S)
end

F.expand!(raw, bp::Matrix) = expand_from_matrix!(raw, bp.A)
function expand_from_matrix!(raw, A)
    top = SparseReflexive(A)
    add_web!(raw, :trophic, (:species, :species), top)
    # This defines new categories of species.
    add_subclass!(raw, :tops, :species, sources_mask(top))
    add_subclass!(raw, :producers, :species, sinks_mask(top))
    add_subclass!(raw, :preys, :species, nonsources_mask(top))
    add_subclass!(raw, :consumers, :species, nonsinks_mask(top))
    # And also new webs with special trophic links highlighted.
    # XXX: import herbivory etc. here.
end

#-------------------------------------------------------------------------------------------
# From ajacency list.

mutable struct Adjacency <: Blueprint
    A::@GraphData {Adjacency}{:bin} # (refs are either numbers or names)
    species::Brought(Species)
    Adjacency(A, sp = Species) = new(@tographdata(A, {Adjacency}{:bin}), sp)
end

# Infer number or names of species from the lists.
F.implied_blueprint_for(bp::Adjacency, ::_Species) = Species(refspace(bp.A))

@blueprint Adjacency "adjacency list of trophic links"
export Adjacency

function F.late_check(raw, bp::Adjacency)
    (; A) = bp
    index = @ref raw.species.index
    @check_list_refs A :species index
end

function F.expand!(raw, bp::Adjacency)
    index = @ref raw.species.index
    A = to_sparse_matrix(bp.A, index, index)
    expand_from_matrix!(raw, A)
end

end

# ==========================================================================================
# Component and generic constructors.

@component Foodweb{Internal} requires(Species) blueprints(Foodweb_)
# Consistency alias.
const (TrophicLayer, _TrophicLayer) = (Foodweb, _Foodweb)
export Foodweb, TrophicLayer

# Precise edges specifications.
function (::_Foodweb)(A)
    A = @tographdata A {SparseMatrix, Adjacency}{:bin}
    if A isa AbstractMatrix
        Foodweb.Matrix(A)
    else
        Foodweb.Adjacency(A)
    end
end

# Construct blueprint from a random model.
function (::_Foodweb)(model::Union{Symbol,AbstractString}; kwargs...)
    model = @tographdata model Y{}
    @kwargs_helpers kwargs

    given(:S) || argerr("Random foodweb models require a number of species 'S'.")
    S = take!(:S)

    # Default values.
    rc = take_or!(:reject_cycles, false)
    rd = take_or!(:reject_if_disconnected, true)
    max = take_or!(:max_iterations, 10^5)

    A = @expand_symbol(
        model,

        #-----------------------------------------------------------------------------------
        # Niche model.

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

                    # HERE: time to extract these from old internals.
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

        #-----------------------------------------------------------------------------------
        # Cascade model.

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

    Foodweb.Matrix(A)

end

# ==========================================================================================
# Foodweb queries.

@class_properties producer Producer producers Producers depends(Foodweb)
@class_properties consumer Consumer consumers Consumers depends(Foodweb)
@class_properties top Top tops Tops depends(Foodweb)
@class_properties prey Prey preys Preys depends(Foodweb)

module FoodwebMethods # (to not pollute global scope)

using SparseArrays
include("./modules_identifiers.jl")
import EcologicalNetworksDynamics:
    EcologicalNetworksDynamics,
    Framework,
    Internal,
    Model,
    Networks,
    Views,
    argerr,
    @method,
    @get,
    @ref,
    @propspace
using .Framework
using .Networks
using .Views
import ..Foodweb

(false) && (local trophic, producers, Producers, consumers, Consumers) # (reassure JuliaLS)
@propspace trophic

#-------------------------------------------------------------------------------------------
# Basic queries.

web(m::Internal) = Networks.web(m, :trophic)
topology(m::Internal) = web(m).topology
number(m::Internal) = m |> topology |> n_edges
mask(::Internal, m::Model) = edges_mask_view(m, :trophic)
levels(m::Internal) = m |> Internals.trophic_levels # HERE: extract from internals.
@method topology depends(Foodweb) read_as(trophic._topology)
@method mask depends(Foodweb) read_as(A, trophic.A, trophic.matrix, trophic.mask)
@method number depends(Foodweb) read_as(trophic.n_links, trophic.n_edges)

#-------------------------------------------------------------------------------------------
# Get a sparse matrix highlighting only the producer-to-producer links.
# HERE: upgrade to a derived extra web within the network.

function producers_matrix(raw::Internal)
    S = @get raw.S
    prods = @get raw.producers.indices
    res = spzeros(Bool, S, S)
    for i in prods, j in prods
        res[i, j] = true
    end
    res
end
@method producers_matrix depends(Foodweb) read_as(producers.matrix)

#-------------------------------------------------------------------------------------------
# Get a sparse matrix highlighting only 'herbivorous' trophic links: consumers-to-producers.
#                                    or 'carnivorous' trophic links: consumers-to-consumers.

function herbivory_matrix(raw::Internal)
    S = @get raw.S
    A = @ref raw.A
    res = spzeros(Bool, S, S)
    preds, preys, _ = findnz(A)
    for (pred, prey) in zip(preds, preys)
        is_producer(raw, prey) && (res[pred, prey] = true)
    end
    res
end
@method herbivory_matrix depends(Foodweb) read_as(trophic.herbivory_matrix)

function carnivory_matrix(raw::Internal)
    S = @get raw.S
    A = @ref raw.A
    res = spzeros(Bool, S, S)
    preds, preys, _ = findnz(A)
    for (pred, prey) in zip(preds, preys)
        is_consumer(raw, prey) && (res[pred, prey] = true)
    end
    res
end
@method carnivory_matrix depends(Foodweb) read_as(trophic.carnivory_matrix)

end

# ==========================================================================================

# Display.
function F.shortline(io::IO, model::Model, ::_Foodweb)
    l = model.trophic.n_links
    p = model.producers.number
    c = model.consumers.number
    r = model.preys.number
    t = model.tops.number
    n(n) = n > 0 ? "$n" : "no"
    s(n) = n > 1 ? "s" : ""
    print(
        io,
        "Foodweb: $(n(l)) link$(s(l)), \
         $(n(p)) producer$(s(p)), \
         $(n(c)) consumer$(s(c)), \
         $(n(r)) prey$(s(r)), \
         $(n(t)) top$(s(t)).",
    )
end

# ==========================================================================================

@doc """
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
""" Foodweb
