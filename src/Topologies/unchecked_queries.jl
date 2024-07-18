# Basic queries all assume that input references are valid.
# Namespace them all under this module as they share this property.
# Methods that would leak references are protected with a '_' prefix.
module Unchecked

import ..Topologies: Topology, Tombstone, Abs, Rel, AbsRef, RelRef, IRef

const imap = Iterators.map
const ifilter = Iterators.filter
idmap(x) = imap(identity, x) # Useful to not leak refs to private collections.

# ==========================================================================================
# Types.

node_type_label(g::Topology, i::Int) = g.node_types_labels[i]
node_type_index(g::Topology, lab::Symbol) = g.node_types_index[lab]
node_type_label(::Topology, lab::Symbol) = lab
node_type_index(::Topology, i::Int) = i
edge_type_label(g::Topology, i::Int) = g.edge_types_labels[i]
edge_type_index(g::Topology, lab::Symbol) = g.edge_types_index[lab]
edge_type_label(::Topology, lab::Symbol) = lab
edge_type_index(::Topology, i::Int) = i

# ==========================================================================================
# Nodes.

# General information.
n_nodes(g::Topology, type::IRef) = g.n_nodes[node_type_index(g, type)]
n_nodes_including_removed(g::Topology, type::IRef) =
    length(g.nodes_types[node_type_index(g, type)])
_nodes_abs_range(g::Topology, type::IRef) =  # Okay to leak (immutable) but not abs-wrapped..
    g.nodes_types[node_type_index(g, type)]
nodes_abs_indices(g::Topology, type::IRef) =
    imap(Abs, g.nodes_types[node_type_index(g, type)])
_nodes_labels(g::Topology, type::IRef) = g.nodes_labels[_nodes_abs_range(g, type)]
node_labels(g::Topology, type::IRef) = idmap(_nodes_labels(g, type))

# Particular information about nodes.
node_label(g::Topology, abs::Abs) = g.nodes_labels[abs.i]
node_label(::Topology, lab::Symbol) = lab
node_label(g::Topology, (rel, type)::Tuple{RelRef,IRef}) =
    node_label(g, node_abs_index(g, rel, type))
node_abs_index(g::Topology, label::Symbol) = Abs(g.nodes_index[label])
node_abs_index(::Topology, abs::Abs) = abs
# Append correct offset to convert between relative / absolute indices.
first_node_abs_index(g::Topology, type::IRef) = first(nodes_abs_indices(g, type))
node_index_offset(g::Topology, type::IRef) = first_node_abs_index(g, type).i - 1
node_abs_index(g::Topology, relative_index::Rel, type::IRef) =
    Abs(relative_index.i + node_index_offset(g, type))
node_rel_index(g::Topology, node::AbsRef, type::IRef) =
    Rel(node_abs_index(g, node).i - node_index_offset(g, type))
node_abs_index(g::Topology, (rel, type)::Tuple{Rel,IRef}) = node_abs_index(g, rel, type)
# For consistency, ignore the node type if not useful, ASSUMING it has been checked.
node_abs_index(g::Topology, (lab, _)::Tuple{Symbol,IRef}) = node_abs_index(g, lab)

# Querying node type requires a linear search,
# but it is generally assumed that if you know the node, then you already know its type.
type_index_of_node(g::Topology, node::AbsRef) =
    findfirst(range -> node_abs_index(g, node).i in range, g.nodes_types)
type_of_node(g::Topology, node::AbsRef) = node_type_label(g, type_index_of_node(g, node))
# But it is O(1) to check whether a given node is of the given type.
function is_node_of_type(g::Topology, node::AbsRef, type::IRef)
    i_type = node_type_index(g, type)
    i_node = node_abs_index(g, node)
    i_node.i in g.nodes_types[i_type]
end

is_removed(g::Topology, node::AbsRef) = g.outgoing[node_abs_index(g, node).i] isa Tombstone
is_live(g::Topology, node::AbsRef) = !is_removed(g, node)

# Iterate over only live nodes (absolute indices).
live_node_indices(g::Topology, type::IRef) =
    imap(Abs, ifilter(_nodes_abs_range(g, type)) do i
        is_live(g, Abs(i))
    end)
live_node_labels(g::Topology, type::IRef) =
    imap(live_node_indices(g, type)) do i
        node_label(g, i)
    end

# ==========================================================================================
# Edges.

n_edges(g::Topology, type) = g.n_edges[edge_type_index(g, type)]

# Direct neighbourhood when querying particular edge type.
# (assuming focal node is not a tombstone)
function _outgoing_indices(g::Topology, node::AbsRef, edge_type::IRef)
    i_type = edge_type_index(g, edge_type)
    _outgoing_indices(g, node)[i_type]
end
function _incoming_indices(g::Topology, node::AbsRef, edge_type::IRef)
    i_type = edge_type_index(g, edge_type)
    _incoming_indices(g, node)[i_type]
end
outgoing_indices(g::Topology, node::AbsRef, type::IRef) =
    imap(Abs, _outgoing_indices(g, node, type))
incoming_indices(g::Topology, node::AbsRef, type::IRef) =
    imap(Abs, _incoming_indices(g, node, type))
outgoing_labels(g::Topology, node::AbsRef, type::IRef) =
    imap(i -> g.nodes_labels[i], _outgoing_indices(g, node, type))
incoming_labels(g::Topology, node, type::IRef) =
    imap(i -> g.nodes_labels[i], _incoming_indices(g, node, type))

# Direct neighbourhood: return twolevel slices:
# first a slice over edge types, then nested neighbours with this edge type.
# (assuming focal node is not a tombstone)
function _outgoing_indices(g::Topology, node::AbsRef)
    i_node = node_abs_index(g, node)
    g.outgoing[i_node.i]
end
function _incoming_indices(g::Topology, node::AbsRef)
    i_node = node_abs_index(g, node)
    g.incoming[i_node.i]
end
outgoing_indices(g::Topology, node::AbsRef) =
    imap(enumerate(_outgoing_indices(g, node))) do (i_edge_type, _neighbours)
        (i_edge_type, imap(Abs, _neighbours))
    end
incoming_indices(g::Topology, node::AbsRef) =
    imap(enumerate(_incoming_indices(g, node))) do (i_edge_type, _neighbours)
        (i_edge_type, imap(Abs, _neighbours))
    end
outgoing_labels(g::Topology, node::AbsRef) =
    imap(enumerate(_outgoing_indices(g, node))) do (i_edge, _neighbours)
        (g.edge_types_labels[i_edge], imap(i_node -> g.nodes_labels[i_node], _neighbours))
    end
incoming_labels(g::Topology, node::AbsRef) =
    imap(enumerate(_incoming_indices(g, node))) do (i_edge, _neighbours)
        (g.edge_types_labels[i_edge], imap(i_node -> g.nodes_labels[i_node], _neighbours))
    end


# Filter adjacency iterators given one particular edge type.
# Also return twolevel iterators: focal node, then its neighbours.
function _outgoing_edges_indices(g::Topology, edge_type::IRef)
    i_type = edge_type_index(g, edge_type)
    imap(ifilter(enumerate(g.outgoing)) do (_, node)
        !(node isa Tombstone)
    end) do (i, _neighbours)
        (i, _neighbours[i_type])
    end
end
function _incoming_edges_indices(g::Topology, edge_type::IRef)
    i_type = edge_type_index(g, edge_type)
    imap(ifilter(enumerate(g.incoming)) do (_, node)
        !(node isa Tombstone)
    end) do (i, _neighbours)
        (i, _neighbours[i_type])
    end
end
outgoing_edges_indices(g::Topology, edge_type::IRef) =
    imap(_outgoing_edges_indices(g, edge_type)) do (i_node, _neighbours)
        (Abs(i_node), imap(Abs, _neighbours))
    end
incoming_edges_indices(g::Topology, edge_type::IRef) =
    imap(_incoming_edges_indices(g, edge_type)) do (i_node, _neighbours)
        (Abs(i_node), imap(Abs, _neighbours))
    end
outgoing_edges_labels(g::Topology, edge_type::IRef) =
    imap(_outgoing_edges_indices(g, edge_type)) do (i_node, _neighbours)
        (node_label(g, i_node), imap(i -> node_label(g, i), _neighbours))
    end
incoming_edges_labels(g::Topology, edge_type::IRef) =
    imap(_incoming_edges_indices(g, edge_type)) do (i_node, _neighbours)
        (node_label(g, i_node), imap(i -> node_label(g, i), _neighbours))
    end

# Same, but filters for one particular node type.
function outgoing_edges_indices(g::Topology, edge_type::IRef, node_type::IRef)
    i_et = edge_type_index(g, edge_type)
    range = _nodes_abs_range(g, node_type)
    imap(ifilter(zip(range, g.outgoing[range])) do (_, node)
        !(node isa Tombstone)
    end) do (i_node, _neighbours)
        (Abs(i_node), imap(Abs, ifilter(in(range), _neighbours[i_et])))
    end
end
function incoming_edges_indices(g::Topology, edge_type::IRef, node_type::IRef)
    i_et = edge_type_index(g, edge_type)
    range = _nodes_abs_range(g, node_type)
    imap(ifilter(zip(range, g.incoming[range])) do (_, node)
        !(node isa Tombstone)
    end) do (i_node, _neighbours)
        (Abs(i_node), imap(Abs, ifilter(in(range), _neighbours[i_et])))
    end
end
outgoing_edges_labels(g::Topology, edge_type::IRef, node_type::IRef) =
    imap(outgoing_edges_indices(g, edge_type, node_type)) do (i_node, neighbours)
        (node_label(g, i_node), imap(i -> node_label(g, i), neighbours))
    end
incoming_edges_labels(g::Topology, edge_type::IRef, node_type::IRef) =
    imap(incoming_edges_indices(g, edge_type, node_type)) do (i_node, neighbours)
        (node_label(g, i_node), imap(i -> node_label(g, i), neighbours))
    end

function has_edge(g::Topology, type, source::AbsRef, target::AbsRef)
    type = edge_type_index(g, type)
    source = node_abs_index(g, source)
    target = node_abs_index(g, target)
    target.i in g.outgoing[source.i][type]
end

end
