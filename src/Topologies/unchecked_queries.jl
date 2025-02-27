# Basic queries all assume that input references are valid
# so they don't need to check input with implicit tests
# and don't bother with producing error messages.
# Namespace them all under this module as they share this property.
# Methods that would leak references are protected with a '_' prefix.
module Unchecked

import ..Topologies: Topology as G, Tombstone, Abs, Rel, AbsRef, RelRef, IRef

const imap = Iterators.map
const ifilter = Iterators.filter
idmap(x) = imap(identity, x) # Useful to not leak refs to private collections.

# ==========================================================================================
# Types.

node_type_label(g::G, i::Int) = g.node_types_labels[i]
node_type_index(g::G, lab::Symbol) = g.node_types_index[lab]
node_type_label(::G, lab::Symbol) = lab
node_type_index(::G, i::Int) = i
edge_type_label(g::G, i::Int) = g.edge_types_labels[i]
edge_type_index(g::G, lab::Symbol) = g.edge_types_index[lab]
edge_type_label(::G, lab::Symbol) = lab
edge_type_index(::G, i::Int) = i

# ==========================================================================================
# Nodes.

# General information.
n_nodes(g::G, type::IRef) = g.n_nodes[node_type_index(g, type)]
n_nodes_including_removed(g::G, type::IRef) =
    length(g.nodes_types[node_type_index(g, type)])
_nodes_abs_range(g::G, type::IRef) =  # Okay to leak (immutable) but not abs-wrapped..
    g.nodes_types[node_type_index(g, type)]
nodes_abs_indices(g::G, type::IRef) = imap(Abs, g.nodes_types[node_type_index(g, type)])
_nodes_labels(g::G, type::IRef) = g.nodes_labels[_nodes_abs_range(g, type)]
node_labels(g::G, type::IRef) = idmap(_nodes_labels(g, type))

# Particular information about nodes.
node_label(g::G, i::Abs) = g.nodes_labels[i.abs]
node_label(::G, lab::Symbol) = lab
node_label(g::G, (rel, type)::Tuple{RelRef,IRef}) =
    node_label(g, node_abs_index(g, rel, type))
node_abs_index(g::G, label::Symbol) = Abs(g.nodes_index[label])
node_abs_index(::G, abs::Abs) = abs
# Append correct offset to convert between relative / absolute indices.
first_node_abs_index(g::G, type::IRef) = first(nodes_abs_indices(g, type))
node_index_offset(g::G, type::IRef) = first_node_abs_index(g, type).abs - 1
node_abs_index(g::G, relative_index::Rel, type::IRef) =
    Abs(relative_index.rel + node_index_offset(g, type))
node_rel_index(g::G, node::AbsRef, type::IRef) =
    Rel(node_abs_index(g, node).abs - node_index_offset(g, type))
node_abs_index(g::G, (rel, type)::Tuple{Rel,IRef}) = node_abs_index(g, rel, type)
# For consistency, ignore the node type if not useful, ASSUMING it has been checked.
node_abs_index(g::G, (lab, _)::Tuple{Symbol,IRef}) = node_abs_index(g, lab)

# Querying node type requires a linear search,
# but it is generally assumed that if you know the node, then you already know its type.
type_index_of_node(g::G, node::AbsRef) =
    findfirst(range -> node_abs_index(g, node).abs in range, g.nodes_types)
type_of_node(g::G, node::AbsRef) = node_type_label(g, type_index_of_node(g, node))
# But it is O(1) to check whether a given node is of the given type.
function is_node_of_type(g::G, node::AbsRef, type::IRef)
    i_type = node_type_index(g, type)
    i_node = node_abs_index(g, node)
    i_node.abs in g.nodes_types[i_type]
end

is_removed(g::G, node::AbsRef) = g.outgoing[node_abs_index(g, node).abs] isa Tombstone
is_live(g::G, node::AbsRef) = !is_removed(g, node)

# Iterate over only live nodes (absolute indices).
live_node_indices(g::G, type::IRef) = imap(Abs, ifilter(_nodes_abs_range(g, type)) do i
    is_live(g, Abs(i))
end)
live_node_labels(g::G, type::IRef) =
    imap(live_node_indices(g, type)) do i
        node_label(g, i)
    end

# ==========================================================================================
# Edges.

n_edges(g::G, type) = g.n_edges[edge_type_index(g, type)]

# Direct neighbourhood when querying particular edge type.
# (assuming focal node is not a tombstone)
function _outgoing_indices(g::G, node::AbsRef, edge_type::IRef)
    i_type = edge_type_index(g, edge_type)
    _outgoing_indices(g, node)[i_type]
end
function _incoming_indices(g::G, node::AbsRef, edge_type::IRef)
    i_type = edge_type_index(g, edge_type)
    _incoming_indices(g, node)[i_type]
end
outgoing_indices(g::G, node::AbsRef, type::IRef) =
    imap(Abs, _outgoing_indices(g, node, type))
incoming_indices(g::G, node::AbsRef, type::IRef) =
    imap(Abs, _incoming_indices(g, node, type))
outgoing_labels(g::G, node::AbsRef, type::IRef) =
    imap(i -> g.nodes_labels[i], _outgoing_indices(g, node, type))
incoming_labels(g::G, node, type::IRef) =
    imap(i -> g.nodes_labels[i], _incoming_indices(g, node, type))

# Direct neighbourhood: return twolevel slices:
# first a slice over edge types, then nested neighbours with this edge type.
# (assuming focal node is not a tombstone)
function _outgoing_indices(g::G, node::AbsRef)
    i_node = node_abs_index(g, node)
    g.outgoing[i_node.abs]
end
function _incoming_indices(g::G, node::AbsRef)
    i_node = node_abs_index(g, node)
    g.incoming[i_node.abs]
end
outgoing_indices(g::G, node::AbsRef) =
    imap(enumerate(_outgoing_indices(g, node))) do (i_edge_type, _neighbours)
        (i_edge_type, imap(Abs, _neighbours))
    end
incoming_indices(g::G, node::AbsRef) =
    imap(enumerate(_incoming_indices(g, node))) do (i_edge_type, _neighbours)
        (i_edge_type, imap(Abs, _neighbours))
    end
outgoing_labels(g::G, node::AbsRef) =
    imap(enumerate(_outgoing_indices(g, node))) do (i_edge, _neighbours)
        (g.edge_types_labels[i_edge], imap(i_node -> g.nodes_labels[i_node], _neighbours))
    end
incoming_labels(g::G, node::AbsRef) =
    imap(enumerate(_incoming_indices(g, node))) do (i_edge, _neighbours)
        (g.edge_types_labels[i_edge], imap(i_node -> g.nodes_labels[i_node], _neighbours))
    end


# Filter adjacency iterators given one particular edge type.
# Also return twolevel iterators: focal node, then its neighbours.
function _outgoing_adjacency(g::G, edge_type::IRef)
    i_type = edge_type_index(g, edge_type)
    imap(ifilter(enumerate(g.outgoing)) do (_, node)
        !(node isa Tombstone)
    end) do (i, _neighbours)
        (i, _neighbours[i_type])
    end
end
function _incoming_adjacency(g::G, edge_type::IRef)
    i_type = edge_type_index(g, edge_type)
    imap(ifilter(enumerate(g.incoming)) do (_, node)
        !(node isa Tombstone)
    end) do (i, _neighbours)
        (i, _neighbours[i_type])
    end
end
outgoing_adjacency(g::G, edge_type::IRef) =
    imap(_outgoing_adjacency(g, edge_type)) do (i_node, _neighbours)
        (Abs(i_node), imap(Abs, _neighbours))
    end
incoming_adjacency(g::G, edge_type::IRef) =
    imap(_incoming_adjacency(g, edge_type)) do (i_node, _neighbours)
        (Abs(i_node), imap(Abs, _neighbours))
    end
outgoing_adjacency_labels(g::G, edge_type::IRef) =
    imap(_outgoing_adjacency(g, edge_type)) do (i_node, _neighbours)
        (node_label(g, i_node), imap(i -> node_label(g, i), _neighbours))
    end
incoming_edges_labels(g::G, edge_type::IRef) =
    imap(_incoming_adjacency(g, edge_type)) do (i_node, _neighbours)
        (node_label(g, i_node), imap(i -> node_label(g, i), _neighbours))
    end

# Same, but query particular end nodes types.
function outgoing_adjacency(g::G, source_type::IRef, edge_type::IRef, target_type::IRef)
    i_et = edge_type_index(g, edge_type)
    src_range = _nodes_abs_range(g, source_type)
    tgt_range = _nodes_abs_range(g, target_type)
    imap(
        ifilter(zip(src_range, g.outgoing[src_range])) do (_, node)
            !(node isa Tombstone)
        end,
    ) do (i_node, _neighbours)
        (Abs(i_node), imap(Abs, ifilter(in(tgt_range), _neighbours[i_et])))
    end
end
function incoming_adjacency(g::G, source_type::IRef, edge_type::IRef, target_type::IRef)
    i_et = edge_type_index(g, edge_type)
    src_range = _nodes_abs_range(g, source_type)
    tgt_range = _nodes_abs_range(g, target_type)
    imap(
        ifilter(zip(tgt_range, g.incoming[tgt_range])) do (_, node)
            !(node isa Tombstone)
        end,
    ) do (i_node, _neighbours)
        (Abs(i_node), imap(Abs, ifilter(in(src_range), _neighbours[i_et])))
    end
end
outgoing_adjacency_labels(g::G, source_type::IRef, edge_type::IRef, target_type::IRef) =
    imap(outgoing_adjacency(g, source_type, edge_type, target_type)) do (i_node, neighbours)
        (node_label(g, i_node), imap(i -> node_label(g, i), neighbours))
    end
incoming_adjacency_labels(g::G, source_type::IRef, edge_type::IRef, target_type::IRef) =
    imap(incoming_adjacency(g, source_type, edge_type, target_type)) do (i_node, neighbours)
        (node_label(g, i_node), imap(i -> node_label(g, i), neighbours))
    end

function has_edge(g::G, type, source::AbsRef, target::AbsRef)
    type = edge_type_index(g, type)
    source = node_abs_index(g, source)
    target = node_abs_index(g, target)
    target.abs in g.outgoing[source.abs][type]
end

end
