# Here are topology-related methods
# that are dedicated to topologies extracted from the ecological model,
# ie. with :species / :trophic compartments *etc.*

# Retrieve underlying model topology.
@expose_data graph begin
    property(topology)
    ref(m -> m.topology)
    get(m -> deepcopy(m.topology))
end

# Convenience local aliases.
const T = Topologies
const U = Topologies.Unchecked
const imap = Iterators.map
const ifilter = Iterators.filter

# Re-export from Topologies.
export disconnected_components

include("./basic_topology_queries.jl")

"""
    remove_species!(g::Topology, node::Symbol)

Remove the given species from the topology.
The species name will remain in-place so that integer-based-indexing remains stable,
but it will be replaced with a tombstone
and all incoming and outgoing links will be forgotten.
"""
function remove_species!(g::Topology, node::T.IRef)
    check_species(g)
    T.remove_node!(g, T.relative(node), :species)
end
export remove_species!

"""
    restrict_to_live_species!(g::Topology, biomasses; threshold = 0)

Remove species nodes until only species with "live" biomasses remain
*i.e.* biomasses above the given threshold.
"""
function restrict_to_live_species!(g::Topology, biomasses; threshold = 0)
    # Rely on species index memory to map biomass values to labels,
    # even though some species may already have been removed.
    check_species(g)
    sp = U.node_type_index(g, :species)
    no = U.n_nodes_including_removed(g, sp)
    nb = length(biomasses)
    if no != nb
        n_live = U.n_nodes(g, sp)
        rem = n_live == no ? "" : " ($(no - n_live) removed)"
        argerr("The given topology indexes $no species$rem, \
                but the given biomasses vector size is $nb.")
    end
    for (i_sp, bm) in zip(U.nodes_abs_indices(g, sp), biomasses)
        rm = U.is_removed(g, i_sp)
        if bm > threshold
            rm && argerr("Species $(repr(U.node_label(g, i_sp))) \
                          has been removed from this topology, \
                          but its biomass is still above threshold: $bm > $threshold.")
        else
            rm || T._remove_node!(g, i_sp, sp)
        end
    end
    g
end
export restrict_to_live_species!

"""
    isolated_producers(m::Model, g::Topology)

Iterate over isolated producers nodes in the topology
*i.e.* producers without incoming or outgoing edges.
"""
function isolated_producers(m::InnerParms, g::Topology)
    sp = U.node_type_index(g, :species)
    abs(i_rel) = U.node_abs_index(g, T.Rel(i_rel), sp)
    unwrap(i) = i.abs
    imap(unwrap, ifilter(imap(abs, get_producers_indices(m))) do i_prod
        inc = g.incoming[i_prod.abs]
        inc isa T.Tombstone && return false
        any(!isempty, inc) && return false
        out = g.outgoing[i_prod.abs]
        any(!isempty, out) && return false
        true
    end)
end
@method isolated_producers depends(Foodweb)
export isolated_producers

"""
    starving_consumers(m::Model, g::Topology)

Iterate over starving consumers nodes in the topology
*i.e.* consumers with no directed trophic path to a consumer.
"""
function starving_consumers(m::InnerParms, g::Topology)
    sp = U.node_type_index(g, :species)
    tr = U.edge_type_index(g, :trophic)
    abs(i_rel) = U.node_abs_index(g, T.Rel(i_rel), sp)
    rel(i_abs) = U.node_rel_index(g, i_abs, sp).rel
    live(i_abs) = U.is_live(g, i_abs)
    unwrap(i) = i.abs

    # Collect all current (live) producers and consumers.
    producers = collect(ifilter(live, imap(abs, get_producers_indices(m))))
    consumers = Set(ifilter(live, imap(abs, get_consumers_indices(m))))

    # Visit the graph from producers up to consumers,
    # and remove all consumers founds.
    to_visit = producers
    found = Set{T.Abs}()
    while !isempty(to_visit)
        i = pop!(to_visit)
        if is_consumer(m, rel(i))
            pop!(consumers, i)
        end
        push!(found, i)
        for up in U.incoming_indices(g, i, tr)
            up in found && continue
            push!(to_visit, up)
        end
    end

    # The remaining consumers are starving.
    imap(unwrap, consumers)
end
@method starving_consumers depends(Foodweb)
export starving_consumers

# Retrieve directly from a solution,
# with the correct extinct species removed.
"""
    get_topology(sol::Solution)

Retrieve network topology from a trajectory solution,
with the extinct species removed.
"""
function get_topology(sol::Solution)
    m = get_model(sol)
    top = m.topology
    for i_sp in keys(get_extinctions(sol))
        remove_species!(top, i_sp)
    end
    top
end
export get_topology

# ==========================================================================================
# Common checks.
check_node_compartment(g::Topology, lab::Symbol) =
    is_node_type(g, lab) ||
    argerr("The given topology has no $(repr(lab)) node compartment.")
check_edge_compartment(g::Topology, lab::Symbol) =
    is_edge_type(g, lab) ||
    argerr("The given topology has no $(repr(lab)) edge compartment.")

check_species(g::Topology) = check_node_compartment(g, :species)
check_nutrients(g::Topology) = check_node_compartment(g, :nutrients)
check_trophic(g::Topology) = check_edge_compartment(g, :trophic)

function check_species_numbers(m::InnerParms, g::Topology, i_sp)
    a = m.n_species
    b = U.n_nodes_including_removed(g, i_sp)
    a == b || argerr("Mismatch between the number of species nodes \
                      in the given model ($a) and the given topology ($b).")
end
check_species_numbers(m::InnerParms, g::Topology) = # (save the i_sp search when you can)
    check_species_numbers(m, g, U.edge_type_index(:species))
