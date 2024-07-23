# ==========================================================================================
# Counts.

"""
    n_live_species(g::Topology)

Number of live species within the topology.
"""
function n_live_species(g::Topology)
    check_species(g)
    U.n_nodes(g, :species)
end
export n_live_species

"""
    n_live_nutrients(g::Topology)

Number of live nutrients within the topology.
"""
function n_live_nutrients(g::Topology)
    check_nutrients(g)
    U.n_nodes(g, :nutrients)
end
export n_live_nutrients

"""
    n_live_producers(m::Model, g::Topology)

Number of live producers within the topology.
"""
function n_live_producers(m::InnerParms, g::Topology)
    check_species(g)
    sp = U.node_type_index(g, :species)
    check_species_numbers(m, g, sp)
    count = 0
    for i_prod in m.producers_indices
        count += U.is_live(g, (T.Rel(i_prod), sp))
    end
    count
end
@method n_live_producers depends(Foodweb)
export n_live_producers

"""
    n_live_consumers(m::Model, g::Topology)

Number of live consumers within the topology.
"""
function n_live_consumers(m::InnerParms, g::Topology)
    check_species(g)
    sp = U.node_type_index(g, :species)
    check_species_numbers(m, g, sp)
    count = 0
    for i_prod in m.consumers_indices
        count += U.is_live(g, (T.Rel(i_prod), sp))
    end
    count
end
@method n_live_consumers depends(Foodweb)
export n_live_consumers

# ==========================================================================================
# Iterators.

"""
    live_species(g::Topology)

Iterate over relative indices of live species within the topology.
"""
function live_species(g::Topology)
    check_species(g)
    sp = U.node_type_index(g, :species)
    imap(U.live_node_indices(g, sp)) do abs
        U.node_rel_index(g, abs, sp).rel
    end
end
export live_species

"""
    live_nutrients(g::Topology)

Iterate over relative indices of live nutrients within the topology.
"""
function live_nutrients(g::Topology)
    check_nutrients(g)
    nt = U.node_type_index(g, :nutrients)
    imap(U.live_node_indices(g, nt)) do abs
        U.node_rel_index(g, abs, nt).rel
    end
end
export live_nutrients

"""
    live_producers(g::Topology)

Iterate over relative indices of live producer species within the topology.
"""
function live_producers(m::InnerParms, g::Topology)
    check_species(g)
    sp = U.node_type_index(g, :species)
    check_species_numbers(m, g, sp)
    abs(i_rel) = U.node_abs_index(g, T.Rel(i_rel), sp)
    imap(ifilter(imap(abs, m.producers_indices)) do abs_prod
        U.is_live(g, abs_prod)
    end) do abs_prod
        U.node_rel_index(g, abs_prod, sp).rel
    end
end
@method live_producers depends(Foodweb)
export live_producers

"""
    live_consumers(g::Topology)

Iterate over relative indices of live producer species within the topology.
"""
function live_consumers(m::InnerParms, g::Topology)
    check_species(g)
    sp = U.node_type_index(g, :species)
    check_species_numbers(m, g, sp)
    abs(i_rel) = U.node_abs_index(g, T.Rel(i_rel), sp)
    imap(ifilter(imap(abs, m.consumers_indices)) do abs_cons
        U.is_live(g, abs_cons)
    end) do abs_cons
        U.node_rel_index(g, abs_cons, sp).rel
    end
end
@method live_consumers depends(Foodweb)
export live_consumers

"""
    trophic_adjacency(g::Topology)

Produce a two-level iterators yielding predators on first level
and all its preys on the second level.
This only includes :species nodes (and not *eg.* :nutrients).
"""
function trophic_adjacency(g::Topology)
    check_species(g)
    check_trophic(g)
    U.outgoing_edges_labels(g, :trophic, :species)
end
export trophic_adjacency
