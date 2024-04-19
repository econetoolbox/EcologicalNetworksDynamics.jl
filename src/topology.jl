# Here are topology-related methods
# that are dedicated to topologies extracted from the ecological model,
# ie. with :species / :trophic compartments *etc.*

# Convenience local aliases.
const T = Topologies
const U = Topologies.Unchecked
const imap = Iterators.map
const ifilter = Iterators.filter

"""
    get_topology(model::Model; without_species = [], without_nutrients = [])
    get_topology(sol::Solution, date = nothing)

Extract model topology to study topological consequences of extinctions.
When called on a static model, nodes can be explicitly removed during extraction.
When called on a simulation result, extinct nodes are automatically removed
with extra arguments passed to [`extinctions`](@ref).
"""
function get_topology(model::InnerParms; without_species = [], without_nutrients = [])
    @tographdata! without_species K{:bin}
    @tographdata! without_nutrients K{:bin}
    g = deepcopy(model._topology)
    removes = []
    if !isempty(without_species)
        check_species(g)
        spi = model.species_index
        @check_refs_if_list without_species "species" spi
        push!(removes, (:species, without_species, spi))
    end
    if !isempty(without_nutrients)
        check_nutrients(g)
        nti = model.nutrients_index
        @check_refs_if_list without_nutrients "nutrients" nti
        push!(removes, (:nutrients, without_nutrients, nti))
    end
    for (compartment, without, index) in removes
        i_cp = U.node_type_index(g, compartment)
        for node in without
            # TODO: GraphDataInputs should permit to automatically cast to indices
            # and avoid this check.
            i_node = T.Rel(node isa Symbol ? index[node] : node)
            T.remove_node!(g, i_node, i_cp)
        end
    end
    g
end
@method get_topology depends() read_as(topology)

function get_topology(sol::Solution; kwargs...)
    m = get_model(sol)
    g = m.topology
    for i in keys(get_extinctions(sol; kwargs...))
        T.remove_node!(g, T.Rel(i), :species)
    end
    g
end
export get_topology

include("./basic_topology_queries.jl")

"""
    remove_species!(g::Topology, species)

Remove species from the given topology to study topological consequences of extinctions.
Tombstones will remain in place so that species indices remain stable,
but all incoming and outgoin edges will be forgotten.
"""
# TODO: provide a checked transactional vectored version,
# accepting Iterator<index|label> or sparse/dense boolean masks.
function remove_species!(g::Topology, species::Integer)
    check_species(g)
    sp = U.node_type_index(g, :species)
    T.check_node_ref(g, species, sp)
    T.remove_node!(g, T.Rel(species), sp)
end
function remove_species!(g::Topology, species::Union{Symbol,AbstractString,Char})
    check_species(g)
    sp = U.node_type_index(g, :species)
    species = Symbol(species)
    T.check_node_ref(g, species, sp)
    rel = U.node_rel_index(g, species, sp)
    T.remove_node!(g, rel, sp)
end
export remove_species!

"""
    isolated_producers(m::Model; kwargs...)
    isolated_producers(sol::Solution; kwargs...)
    isolated_producers(g::Topology, producers_indices) ⚠*

Iterate over isolated producers nodes,
*i.e.* producers without incoming or outgoing edges,
either in the static model topology or during/after simulation.
See [`topology`](@ref).

  - ⚠ : Assumes consistent indices from the same model: will be removed in a future version.
"""
isolated_producers(m::InnerParms; kwargs...) =
    isolated_producers(get_topology(m; kwargs...), m.producers_indices)
@method isolated_producers depends(Foodweb)

isolated_producers(sol::Solution; kwargs...) =
    isolated_producers(get_topology(sol; kwargs...), get_model(sol).producers_indices)
export isolated_producers

# Unexposed underlying primitive: assumes that indices are consistent within the topology.
function isolated_producers(g::Topology, producers_indices)
    sp = U.node_type_index(g, :species)
    abs(i_rel) = U.node_abs_index(g, T.Rel(i_rel), sp)
    unwrap(i) = i.abs
    imap(unwrap, ifilter(imap(abs, producers_indices)) do i_prod
        inc = g.incoming[i_prod.abs]
        inc isa T.Tombstone && return false
        any(!isempty, inc) && return false
        out = g.outgoing[i_prod.abs]
        any(!isempty, out) && return false
        true
    end)
end

"""
    starving_consumers(m::Model; kwargs...)
    starving_consumers(sol::Solution; kwargs...)
    starving_consumers(g::Topology, producers_indices, consumers_indices) ⚠*

Iterate over starving consumers nodes,
*i.e.* consumers with no directed trophic path to a producer,
either in the static model topology
or after simulation.
See [`topology`](@ref).

  - ⚠ : Assumes consistent indices from the same model: will be removed in a future version.
"""
starving_consumers(m::InnerParms; kwargs...) =
    starving_consumers(get_topology(m; kwargs...), m.producers_indices, m.consumers_indices)
@method starving_consumers depends(Foodweb)

function starving_consumers(sol::Solution; kwargs...)
    (; producers_indices, consumers_indices) = get_model(sol)
    starving_consumers(get_topology(sol; kwargs...), producers_indices, consumers_indices)
end
export starving_consumers

# Unexposed underlying primitive: assumes that indices are consistent within the topology.
function starving_consumers(g::Topology, producers_indices, consumers_indices)
    consumers_indices = Set(consumers_indices)
    sp = U.node_type_index(g, :species)
    tr = U.edge_type_index(g, :trophic)
    abs(i_rel) = U.node_abs_index(g, T.Rel(i_rel), sp)
    rel(i_abs) = U.node_rel_index(g, i_abs, sp).rel
    live(i_abs) = U.is_live(g, i_abs)
    unwrap(i) = i.abs

    # Collect all current (live) producers and consumers.
    producers = Set(ifilter(live, imap(abs, producers_indices)))
    consumers = Set(ifilter(live, imap(abs, consumers_indices)))

    # Visit the graph from producers up to consumers,
    # and remove all consumers founds.
    to_visit = producers
    found = Set{T.Abs}()
    while !isempty(to_visit)
        i = pop!(to_visit)
        if rel(i) in consumers_indices
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

"""
    disconnected_components(m::Model; kwargs...)
    disconnected_components(sol::Model; kwargs...)
    disconnected_components(g::Topology)

Iterate over the disconnected component within the topology.
This create a collection of topologies
with all the same compartments and nodes indices,
but with different nodes marked as removed to constitute the various components.
See [`topology`](@ref).
"""
T.disconnected_components(m::Model; kwargs...) =
    disconnected_components(get_topology(m; kwargs...))
T.disconnected_components(sol::Solution; kwargs...) =
    disconnected_components(get_topology(sol; kwargs...))
# Direct re-export from Topologies.
export disconnected_components
