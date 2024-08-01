# ==========================================================================================
# Counts.

"""
    n_live_species(m::Model; kwargs...)
    n_live_species(sol::Solution; kwargs...)
    n_live_species(g::Topology)

Number of live species within the topology.
See [`topology`](@ref).
"""
function n_live_species(g::Topology)
    check_species(g)
    U.n_nodes(g, :species)
end
n_live_species(m::InnerParms; kwargs...) = n_live_species(get_topology(m; kwargs...))
@method n_live_species depends(Species)
n_live_species(sol::Solution; kwargs...) = n_live_species(get_topology(sol; kwargs...))
export n_live_species

"""
    n_live_nutrients(m::Model; kwargs...)
    n_live_nutrients(sol::Model; kwargs...)
    n_live_nutrients(g::Topology)

Number of live nutrients within the topology.
See [`topology`](@ref).
"""
function n_live_nutrients(g::Topology)
    check_nutrients(g)
    U.n_nodes(g, :nutrients)
end
n_live_nutrients(m::InnerParms; kwargs...) = n_live_nutrients(get_topology(m; kwargs...))
@method n_live_nutrients depends(Nutrients.Nodes)
n_live_nutrients(sol::Solution; kwargs...) = n_live_nutrients(get_topology(sol; kwargs...))
export n_live_nutrients

#-------------------------------------------------------------------------------------------
# Foodweb-dependent: can't work only with a `Topology` value because static species
# properties are needed, and these are only stored within the model,
# not in the topology with species removed.

# TODO: the following code is DUPLICATED for producers/consumers/preys/tops: factorize.
"""
    n_live_producers(m::Model; kwargs...)
    n_live_producers(sol::Solution; kwargs...)
    n_live_producers(g::Topology, producers_indices) ⚠*

Number of live producers within the topology after simulation.
See [`topology`](@ref).
⚠*: Assumes consistent indices from the same model: will be removed in a future version.
"""
n_live_producers(m::InnerParms; kwargs...) =
    n_live_producers(get_topology(m; kwargs...), m.producers_indices)
@method n_live_producers depends(Foodweb)
n_live_producers(sol::Solution; kwargs...) =
    n_live_producers(get_topology(sol; kwargs...), get_model(sol).producers_indices)
function n_live_producers(g::Topology, producers_indices)
    check_species(g)
    sp = U.node_type_index(g, :species)
    count = 0
    for i_prod in producers_indices
        count += U.is_live(g, (T.Rel(i_prod), sp))
    end
    count
end
export n_live_producers

"""
    n_live_consumers(m::Model; kwargs...)
    n_live_consumers(sol::Solution; kwargs...)
    n_live_consumers(g::Topology, consumers_indices) ⚠*

Number of live consumers within the topology after simulation.
See [`topology`](@ref).
⚠*: Assumes consistent indices from the same model: will be removed in a future version.
"""
n_live_consumers(m::InnerParms; kwargs...) =
    n_live_consumers(get_topology(m; kwargs...), m.consumers_indices)
@method n_live_consumers depends(Foodweb)
n_live_consumers(sol::Solution; kwargs...) =
    n_live_consumers(get_topology(sol; kwargs...), get_model(sol).consumers_indices)
function n_live_consumers(g::Topology, consumers_indices)
    check_species(g)
    sp = U.node_type_index(g, :species)
    count = 0
    for i_prod in consumers_indices
        count += U.is_live(g, (T.Rel(i_prod), sp))
    end
    count
end
export n_live_consumers

"""
    n_live_preys(m::Model; kwargs...)
    n_live_preys(sol::Solution; kwargs...)
    n_live_preys(g::Topology, preys_indices) ⚠*

Number of live preys within the topology after simulation.
See [`topology`](@ref).
⚠*: Assumes consistent indices from the same model: will be removed in a future version.
"""
n_live_preys(m::InnerParms; kwargs...) =
    n_live_preys(get_topology(m; kwargs...), m.preys_indices)
@method n_live_preys depends(Foodweb)
n_live_preys(sol::Solution; kwargs...) =
    n_live_preys(get_topology(sol; kwargs...), get_model(sol).preys_indices)
function n_live_preys(g::Topology, preys_indices)
    check_species(g)
    sp = U.node_type_index(g, :species)
    count = 0
    for i_prod in preys_indices
        count += U.is_live(g, (T.Rel(i_prod), sp))
    end
    count
end
export n_live_preys

"""
    n_live_tops(m::Model; kwargs...)
    n_live_tops(sol::Solution; kwargs...)
    n_live_tops(g::Topology, tops_indices) ⚠*

Number of live tops within the topology after simulation.
See [`topology`](@ref).
⚠*: Assumes consistent indices from the same model: will be removed in a future version.
"""
n_live_tops(m::InnerParms; kwargs...) =
    n_live_tops(get_topology(m; kwargs...), m.tops_indices)
@method n_live_tops depends(Foodweb)
n_live_tops(sol::Solution; kwargs...) =
    n_live_tops(get_topology(sol; kwargs...), get_model(sol).tops_indices)
function n_live_tops(g::Topology, tops_indices)
    check_species(g)
    sp = U.node_type_index(g, :species)
    count = 0
    for i_prod in tops_indices
        count += U.is_live(g, (T.Rel(i_prod), sp))
    end
    count
end
export n_live_tops

# ==========================================================================================
# Iterators.

"""
    live_species(m::Model; kwargs...)
    live_species(sol::Solution; kwargs...)
    live_species(g::Topology)

Iterate over relative indices of live species within the topology.
See [`topology`](@ref).
"""
function live_species(g::Topology)
    check_species(g)
    sp = U.node_type_index(g, :species)
    imap(U.live_node_indices(g, sp)) do abs
        U.node_rel_index(g, abs, sp).rel
    end
end
live_species(m::InnerParms; kwargs...) = live_species(get_topology(m; kwargs...))
@method live_species depends(Species)
live_species(sol::Solution; kwargs...) = live_species(get_topology(sol; kwargs...))
export live_species

"""
    live_nutrients(m::Model; kwargs...)
    live_nutrients(sol::Solution; kwargs...)
    live_nutrients(g::Topology)

Iterate over relative indices of live nutrients within the topology.
See [`topology`](@ref).
"""
function live_nutrients(g::Topology)
    check_nutrients(g)
    sp = U.node_type_index(g, :nutrients)
    imap(U.live_node_indices(g, sp)) do abs
        U.node_rel_index(g, abs, sp).rel
    end
end
live_nutrients(m::InnerParms; kwargs...) = live_nutrients(get_topology(m; kwargs...))
@method live_nutrients depends(Nutrients.Nodes)
live_nutrients(sol::Solution; kwargs...) = live_nutrients(get_topology(sol; kwargs...))
export live_nutrients

#-------------------------------------------------------------------------------------------
# Foodweb-dependent (see `Foodweb-dependent` above).

"""
    trophic_adjacency(m::Model; kwargs...)
    trophic_adjacency(sol::Solution; kwargs...)
    trophic_adjacency(g::Topology)

Produce a two-level iterators yielding predators on first level
and all its preys on the second level.
This only includes :species nodes (and not *eg.* :nutrients).
See [`topology`](@ref).
"""
function trophic_adjacency(g::Topology)
    check_species(g)
    check_trophic(g)
    U.outgoing_adjacency_labels(g, :species, :trophic, :species)
end
trophic_adjacency(m::InnerParms; kwargs...) = trophic_adjacency(get_topology(m; kwargs...))
@method trophic_adjacency depends(Foodweb)
trophic_adjacency(sol::Solution; kwargs...) =
    trophic_adjacency(get_topology(sol; kwargs...))
export trophic_adjacency

# TODO: the following code is DUPLICATED for producers/consumers/preys/tops: factorize.
"""
    live_producers(m::Model; kwargs...)
    live_producers(s::Solution; kwargs...)
    live_producers(g::Topology, producers_indices) ⚠*

Iterate over relative indices of live producer species after simulation.
See [`topology`](@ref).
⚠*: Assumes consistent indices from the same model: will be removed in a future version.
"""
live_producers(m::InnerParms; kwargs...) =
    live_producers(get_topology(m; kwargs...), m.producers_indices)
@method live_producers depends(Foodweb)
live_producers(sol::Solution; kwargs...) =
    live_producers(get_topology(sol; kwargs...), get_model(sol).producers_indices)
function live_producers(g::Topology, producers_indices)
    check_species(g)
    sp = U.node_type_index(g, :species)
    abs(i_rel) = U.node_abs_index(g, T.Rel(i_rel), sp)
    imap(ifilter(imap(abs, producers_indices)) do abs_prod
        U.is_live(g, abs_prod)
    end) do abs_prod
        U.node_rel_index(g, abs_prod, sp).rel
    end
end
export live_producers

"""
    live_consumers(m::Model; kwargs...)
    live_consumers(s::Solution; kwargs...)
    live_consumers(g::Topology, consumers_indices) ⚠*

Iterate over relative indices of live consumer species after simulation.
See [`topology`](@ref).
⚠*: Assumes consistent indices from the same model: will be removed in a future version.
"""
live_consumers(m::InnerParms; kwargs...) =
    live_consumers(get_topology(m; kwargs...), m.consumers_indices)
@method live_consumers depends(Foodweb)
live_consumers(sol::Solution; kwargs...) =
    live_consumers(get_topology(sol; kwargs...), get_model(sol).consumers_indices)
function live_consumers(g::Topology, consumers_indices)
    check_species(g)
    sp = U.node_type_index(g, :species)
    abs(i_rel) = U.node_abs_index(g, T.Rel(i_rel), sp)
    imap(ifilter(imap(abs, consumers_indices)) do abs_prod
        U.is_live(g, abs_prod)
    end) do abs_prod
        U.node_rel_index(g, abs_prod, sp).rel
    end
end
export live_consumers

"""
    live_preys(m::Model; kwargs...)
    live_preys(s::Solution; kwargs...)
    live_preys(g::Topology, preys_indices) ⚠*

Iterate over relative indices of live prey species after simulation.
See [`topology`](@ref).
⚠*: Assumes consistent indices from the same model: will be removed in a future version.
"""
live_preys(m::InnerParms; kwargs...) =
    live_preys(get_topology(m; kwargs...), m.preys_indices)
@method live_preys depends(Foodweb)
live_preys(sol::Solution; kwargs...) =
    live_preys(get_topology(sol; kwargs...), get_model(sol).preys_indices)
function live_preys(g::Topology, preys_indices)
    check_species(g)
    sp = U.node_type_index(g, :species)
    abs(i_rel) = U.node_abs_index(g, T.Rel(i_rel), sp)
    imap(ifilter(imap(abs, preys_indices)) do abs_prod
        U.is_live(g, abs_prod)
    end) do abs_prod
        U.node_rel_index(g, abs_prod, sp).rel
    end
end
export live_preys

"""
    live_tops(m::Model; kwargs...)
    live_tops(s::Solution; kwargs...)
    live_tops(g::Topology, tops_indices) ⚠*

Iterate over relative indices of live top species after simulation.
See [`topology`](@ref).
⚠*: Assumes consistent indices from the same model: will be removed in a future version.
"""
live_tops(m::InnerParms; kwargs...) = live_tops(get_topology(m; kwargs...), m.tops_indices)
@method live_tops depends(Foodweb)
live_tops(sol::Solution; kwargs...) =
    live_tops(get_topology(sol; kwargs...), get_model(sol).tops_indices)
function live_tops(g::Topology, tops_indices)
    check_species(g)
    sp = U.node_type_index(g, :species)
    abs(i_rel) = U.node_abs_index(g, T.Rel(i_rel), sp)
    imap(ifilter(imap(abs, tops_indices)) do abs_prod
        U.is_live(g, abs_prod)
    end) do abs_prod
        U.node_rel_index(g, abs_prod, sp).rel
    end
end
export live_tops

# ==========================================================================================
# Adjacency matrices.

"""
    adjacency_matrix(g::Topology, source, edge, target; transpose = false; prune = true)

Produce a boolean sparse matrix representing the connections of the given edge type,
from the given source node compartment (lines) \
to the given target node compartment (colums).
Flip dimensions if `transpose` is set.
Lower `prune` to keep lines and columns for the nodes marked as removed.
See [`topology`](@ref).
"""
function adjacency_matrix(
    g::Topology,
    source::Symbol,
    edge::Symbol,
    target::Symbol;
    transpose = false,
    prune = true,
)
    # Same, but with stricter input signature.
    Topologies.adjacency_matrix(g, source, edge, target; transpose, prune)
end
export adjacency_matrix

"""
    species_adjacency_matrix(g::Topology, edge::Symbol; kwargs...)

Restriction of [`adjacency_matrix`](@ref) to only `:species` compartments.
"""
function species_adjacency_matrix(g::Topology, edge::Symbol; kwargs...)
    adjacency_matrix(g, :species, edge, :species; kwargs...)
end
export species_adjacency_matrix

"""
    foodweb_matrix(g::Topology; kwargs...)

Restriction of [`species_adjacency_matrix`](@ref)
to only `:species` compartment and `:trophic` links.
"""
foodweb_matrix(g::Topology; kwargs...) = species_adjacency_matrix(g, :trophic; kwargs...)
export foodweb_matrix


# ==========================================================================================
# Common checks to raise useful error messages.

check_node_compartment(g::Topology, lab::Symbol) =
    is_node_type(g, lab) ||
    argerr("The given topology has no $(repr(lab)) node compartment.")
check_edge_compartment(g::Topology, lab::Symbol) =
    is_edge_type(g, lab) ||
    argerr("The given topology has no $(repr(lab)) edge compartment.")

check_species(g::Topology) = check_node_compartment(g, :species)
check_nutrients(g::Topology) = check_node_compartment(g, :nutrients)
check_trophic(g::Topology) = check_edge_compartment(g, :trophic)
