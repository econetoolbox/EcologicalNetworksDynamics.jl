module Topologies

using OrderedCollections
using Graphs
using SparseArrays

argerr(mess) = throw(ArgumentError(mess))

# Mark removed nodes.
struct Tombstone end

"""
Values of this type are constructed from a model value,
to represent its pure topology:

  - Nodes identity and types: species, nutrients, patches..
  - Edges types: trophic interaction, non-trophic interactions, migration corridors..

Nodes and edge information can be queried using either labels or indices.

Values of this type are supposed not to be mutated,
as they carry faithful topological information reflecting the model
at the moment it has been extracted from it.

However, nodes *may* be removed to represent *e.g.* species extinction,
and study the topological consequences or removing them.
The indices and labels remain stable after removal,
always consistent with their indices from the model value when extracted.
As a consequence: tombstones remain,
and every node in the topology can be queried
for having been 'removed' or not.
No tombstone remain for edges: once removed, there is no trace left of them.

Node types and edge types constitute the various "compartments" of the topology:
equivalence classes gathering all nodes/edges with the same type.

There are two ways of querying nodes information with indices:

  - Using *absolute* indices, uniquely identifying nodes within the whole topology.
  - Using *relative* indices, uniquely identifying nodes within their *compartment*.

Two newtypes types `Abs` and `Rel` are used in the API to protect against mixing them up.
"""
struct Topology
    # List/index possible types for nodes and edges.
    # Types cannot be removed.
    node_types_labels::Vector{Symbol} # [type index: type label]
    node_types_index::Dict{Symbol,Int} # {type label: type index}
    edge_types_labels::Vector{Symbol}
    edge_types_index::Dict{Symbol,Int}

    # List nodes and their associated types.
    # Nodes are *sorted by type*:
    # so that all nodes with the same type are stored contiguously in this array.
    # Nodes can't be removed from this list, so their indices remain stable.
    nodes_labels::Vector{Symbol} # [node absolute index: node label]
    nodes_index::Dict{Symbol,Int} # {node label: node absolute index}
    nodes_types::Vector{UnitRange{Int}} # [type index: (start, end) of nodes with this type]

    # Topological information: paired, layered adjacency lists.
    # Tombstones marking nodes removal are stored here.
    outgoing::Vector{Union{Tombstone,Vector{OrderedSet{Int}}}}
    incoming::Vector{Union{Tombstone,Vector{OrderedSet{Int}}}}
    # [node: [edgetype: {nodeid}]]
    # ^--------------------------^- : Adjacency list: one entry per node 'N'.
    #        ^-------------------^- : One entry per edge type or a tombstone (removed node).
    #                   ^--------^- : One entry per neighbour of 'N': its absolute index.

    # Cached redundant information
    # that would otherwise be non-O(1) to calculate.
    n_edges::Vector{Int} # Per edge type.
    n_nodes::Vector{Int} # Per node type, not counting tombstones.

    Topology() = new([], Dict(), [], Dict(), [], Dict(), [], [], [], [], [])
end
export Topology

# Wrap an absolute node index.
struct Abs
    abs::Int # Use `.abs` to avoid mistaking with `.rel`.
end

# Wrap a relative node index.
struct Rel
    rel::Int # Use `.rel` to avoid mistaking with `.abs`.
end

# When exposing indices
# explicit whether they mean relative or absolute.
const IRef = Union{Int,Symbol}
const RelRef = Union{Rel,Symbol}
relative(i::Int) = Rel(i)
absolute(i::Int) = Abs(i)
relative(lab::Symbol) = lab
absolute(lab::Symbol) = lab
# A combination of Relative + Node type info constitutes an absolute node ref.
const AbsRef = Union{Abs,Symbol,Tuple{RelRef,IRef}}

# Move boilerplate interface to dedicated files.
include("unchecked_queries.jl")
const U = Unchecked # Official, stable alias to ease refs to unchecked queries.

include("checks.jl")
include("queries.jl")
include("display.jl")

#-------------------------------------------------------------------------------------------
# Construction primitives.

# Only push whole slices of nodes of a new type at once.
function add_nodes!(g::Topology, labels, type::Symbol)

    # Check whole transaction before commiting.
    has_node_type(g, type) &&
        argerr("Node type $(repr(type)) already exists in the topology.")
    has_edge_type(g, type) &&
        argerr("Node type $(repr(type)) would be confused with edge type $(repr(type)).")
    labels = check_new_nodes_labels(g, labels)

    # Add new node type.
    push!(g.node_types_labels, type)
    g.node_types_index[type] = length(g.node_types_labels)

    # Add new associated nodes.
    nindex = g.nodes_index
    nlabs = g.nodes_labels
    n_before = length(nlabs)
    for new_lab in labels
        push!(nlabs, new_lab)
        nindex[new_lab] = length(nlabs)
        for adj in (g.outgoing, g.incoming)
            # Need an entry for every edge type.
            entry = Vector{OrderedSet{Int}}()
            for _ in 1:n_edge_types(g)
                push!(entry, OrderedSet())
            end
            push!(adj, entry)
        end
    end

    # Update value.
    n_after = length(nlabs)
    push!(g.nodes_types, n_before+1:n_after)
    push!(g.n_nodes, n_after - n_before)

    g
end
export add_nodes!

function add_edge_type!(g::Topology, type::Symbol)

    # Check transaction.
    haskey(g.edge_types_index, type) &&
        argerr("Edge type $(repr(type)) already exists in the topology.")
    haskey(g.node_types_index, type) &&
        argerr("Edge type $(repr(type)) would be confused with node type $(repr(type)).")

    # Commit.
    push!(g.edge_types_labels, type)
    g.edge_types_index[type] = length(g.edge_types_labels)
    for adj in (g.outgoing, g.incoming)
        for node in adj
            node isa Tombstone && continue
            push!(node, OrderedSet{Int}())
        end
    end
    push!(g.n_edges, 0)

    g
end
export add_edge_type!

function add_edge!(g::Topology, type::IRef, source::AbsRef, target::AbsRef)
    # Check transaction.
    check_edge_type(g, type)
    check_node_ref(g, source)
    check_node_ref(g, target)
    i_type = U.edge_type_index(g, type)
    i_source = U.node_abs_index(g, source)
    i_target = U.node_abs_index(g, target)
    check_live_node(g, i_source, source)
    check_live_node(g, i_target, target)
    U.has_edge(g, i_type, i_source, i_target) &&
        argerr("There is already an edge of type $(repr(type)) \
                between nodes $(repr(source)) and $(repr(target)).")
    # Commit.
    _add_edge!(g, i_type, i_source, i_target)
end
# (this "commit" part is also used when importing edges from matrices)
function _add_edge!(g::Topology, i_type::Int, i_source::Abs, i_target::Abs)
    push!(g.outgoing[i_source.abs][i_type], i_target.abs)
    push!(g.incoming[i_target.abs][i_type], i_source.abs)
    g.n_edges[i_type] += 1
    g
end
export add_edge!

include("./edges_from_matrices.jl")

#-------------------------------------------------------------------------------------------
# Remove all neighbours of this node and replace it with a tombstone.

# The exposed version is checked.
function remove_node!(g::Topology, node::RelRef, type::IRef)
    # Check transaction.
    check_node_type(g, type)
    check_node_ref(g, node, type)
    i_node = U.node_abs_index(g, (node, type))
    U.is_live(g, i_node) || alreadyerr(node)
    i_type = U.node_type_index(g, type)
    _remove_node!(g, i_node, i_type)
end

# Not specifying the type requires a linear search for it.
function remove_node!(g::Topology, node::AbsRef)
    # Check transaction.
    check_node_ref(g, node)
    i_node = U.node_abs_index(g, node)
    U.is_live(g, i_node) || alreadyerr(node)
    i_type = U.type_index_of_node(g, node)
    _remove_node!(g, i_node, i_type)
end

alreadyerr(node) = argerr("Node $(repr(node)) was already removed from this topology.")

# Commit.
function _remove_node!(g::Topology, i_node::Abs, i_type::Int)
    # Assumes the node is valid and live, and that the type does correspond.
    g.n_edges .-= length.(g.outgoing[i_node.abs])
    g.n_edges .-= length.(g.incoming[i_node.abs])
    ts = Tombstone()
    g.outgoing[i_node.abs] = ts
    g.incoming[i_node.abs] = ts
    for adjacency in (g.outgoing, g.incoming)
        for other in adjacency
            other isa Tombstone && continue
            for neighbours in other
                pop!(neighbours, i_node.abs, nothing)
            end
        end
    end
    g.n_nodes[i_type] -= 1
    g
end

export remove_node!

#-------------------------------------------------------------------------------------------
"""
    adjacency_matrix(
        g::Topology,
        source::Symbol,
        edge::Symbol,
        target::Symbol,
        transpose = false,
        prune = false,
    )

Construct a sparse binary matrix representing a restriction of the topology
to the given source/target nodes compartment and the given edge compartment.
The result entry `[i, j]` is true if edge i → j exist (outgoing matrix).
If `transpose` is set, the entry is true if edge `j → i` exists instead (incoming matrix).
Entries are false if either `i` or `j` has been removed from the topology.
If `prune` is set, remove line/columns corresponding removed nodes.
"""
function adjacency_matrix(
    g::Topology,
    source::Symbol,
    edge::Symbol,
    target::Symbol;
    transpose = false,
    prune = true,
)
    check_node_type(g, source)
    check_node_type(g, target)
    check_edge_type(g, edge)
    si = U.node_type_index(g, source)
    ti = U.node_type_index(g, target)
    ei = U.edge_type_index(g, edge)
    if prune
        pruned_adjacency_matrix(g, si, ei, ti, transpose)
    else
        full_adjacency_matrix(g, si, ei, ti, transpose)
    end
end
export adjacency_matrix

function full_adjacency_matrix(g::Topology, s::Int, e::Int, t::Int, transpose::Bool)
    # Query result dimensions.
    n_source = U.n_nodes_including_removed(g, s)
    n_target = U.n_nodes_including_removed(g, t)
    # Permute on transposition.
    (line, col) = transpose ? (t, s) : (s, t)
    n, m = transpose ? (n_target, n_source) : (n_source, n_target)
    it = transpose ? U.incoming_adjacency(g, s, e, t) : U.outgoing_adjacency(g, s, e, t)
    # Construct matrix.
    res = spzeros(Bool, n, m)
    for (iabs, neighbours) in it
        i = U.node_rel_index(g, iabs, line).rel
        for jabs in neighbours
            j = U.node_rel_index(g, jabs, col).rel
            res[i, j] = true
        end
    end
    res
end

function pruned_adjacency_matrix(g::Topology, s::Int, e::Int, t::Int, transpose::Bool)
    # Watch the mapping from "pre-indices" (before pruning) / "post-indices" (after pruning).
    pre_n_source = U.n_nodes_including_removed(g, s)
    pre_n_target = U.n_nodes_including_removed(g, t)
    post_n_source = U.n_nodes(g, s) # (only live nodes)
    post_n_target = U.n_nodes(g, t)

    if (pre_n_source, pre_n_target) == (post_n_source, post_n_target)
        return full_adjacency_matrix(g, s, e, t, transpose) # (simpler algorithm)
    end

    # Permute on transposition.
    (line, col) = transpose ? (t, s) : (s, t)
    prn, prm = transpose ? (pre_n_target, pre_n_source) : (pre_n_source, pre_n_target)
    n, m = transpose ? (post_n_target, post_n_source) : (post_n_source, post_n_target)

    # One pass nodes to prepare a pre -> index mapping.
    (i_map, j_map) = map([(prn, line), (prm, col)]) do (prn, type)
        map = []
        skips = 0
        for i_pre in 1:prn
            abs = U.node_abs_index(g, Rel(i_pre), type)
            i_post = if U.is_removed(g, abs)
                skips += 1
                0
            else
                i_pre - skips
            end
            push!(map, i_post)
        end
        map
    end

    # One pass over the edges to fill up the result.
    res = spzeros(Bool, n, m)
    it = transpose ? U.incoming_adjacency(g, s, e, t) : U.outgoing_adjacency(g, s, e, t)
    for (iabs, neighbours) in it
        pre_i = U.node_rel_index(g, iabs, line).rel
        i = i_map[pre_i]
        for jabs in neighbours
            pre_j = U.node_rel_index(g, jabs, col).rel
            j = j_map[pre_j]
            res[i, j] = true
        end
    end
    res
end

#-------------------------------------------------------------------------------------------
# Iterate over disconnected components within the topology.
# Every component is yielded as a separate new topology,
# with tombstones in the right places.

function disconnected_components(g::Topology)
    # Construct a simpler graph representation
    # with all nodes and edges compartments pooled together.
    graph = SimpleDiGraph()
    for _ in 1:length(g.nodes_labels)
        add_vertex!(graph)
    end
    for (i_src, et) in enumerate(g.outgoing)
        et isa Tombstone && continue
        for targets in et, i_tgt in targets
            Graphs.add_edge!(graph, i_src, i_tgt)
        end
    end
    # Use it to run disconnection algorithm.
    Iterators.map(
        Iterators.filter(weakly_connected_components(graph)) do component_nodes
            # Removed nodes result in degenerated singleton components.
            # Dismiss them.
            !(length(component_nodes) == 1 && U.is_removed(g, Abs(first(component_nodes))))
        end,
    ) do component_nodes
        # Construct a whole new value with only these nodes remaining.
        new = Topology()
        # All types are copied as-is.
        append!(new.node_types_labels, g.node_types_labels)
        append!(new.edge_types_labels, g.edge_types_labels)
        for (k, v) in g.node_types_index
            new.node_types_index[k] = v
            push!(new.n_nodes, 0)
        end
        for (k, v) in g.edge_types_index
            new.edge_types_index[k] = v
            push!(new.n_edges, 0)
        end
        # All nodes are copied as-is.
        append!(new.nodes_labels, g.nodes_labels)
        append!(new.nodes_types, g.nodes_types)
        for (k, v) in g.nodes_index
            new.nodes_index[k] = v
        end
        # But only the ones in this component are reinserted with their neighbours,
        # the others become tombstones.
        ts = Tombstone()
        component_nodes = Set(component_nodes)
        i_node_type = 1
        for i_node in 1:length(new.nodes_labels)
            if i_node > last(new.nodes_types[i_node_type])
                i_node_type += 1
            end
            inc = g.incoming[i_node]
            out = g.outgoing[i_node]
            if i_node in component_nodes && !(out isa Tombstone)
                new_in = Vector{OrderedSet{Int}}()
                new_out = Vector{OrderedSet{Int}}()
                for (i_edge_type, (in_et, out_et)) in enumerate(zip(inc, out))
                    in_entry = OrderedSet()
                    out_entry = OrderedSet()
                    first = true
                    for (et, entry) in ((in_et, in_entry), (out_et, out_entry))
                        for adj in et
                            adj in component_nodes || continue
                            push!(entry, adj)
                            new.n_edges[i_edge_type] += first
                        end
                        first = false
                    end
                    push!(new_in, in_entry)
                    push!(new_out, out_entry)
                end
                push!(new.incoming, new_in)
                push!(new.outgoing, new_out)
                new.n_nodes[i_node_type] += 1
            else
                push!(new.incoming, ts)
                push!(new.outgoing, ts)
            end
        end
        new
    end
end
export disconnected_components

# Compare for equality field-by-field.
function Base.:(==)(a::Topology, b::Topology)
    for fname in fieldnames(Topology)
        fa, fb = getfield.((a, b), fname)
        fa == fb || return false
    end
    true
end

end
