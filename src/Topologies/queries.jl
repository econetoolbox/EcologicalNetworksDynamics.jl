# Build over the Unchecked module and checking functions
# to expose checked queries.

const imap = Iterators.map
idmap(x) = imap(identity, x) # Useful to not leak refs to private collections.

# Information about types.
n_node_types(g::Topology) = length(g.node_types_labels)
n_edge_types(g::Topology) = length(g.edge_types_labels)
export n_node_types, n_edge_types

_node_types(g::Topology) = g.node_types_labels
_edge_types(g::Topology) = g.edge_types_labels
node_types(g::Topology) = idmap(_node_types(g))
edge_types(g::Topology) = idmap(_edge_types(g))
export node_types, edge_types

is_node_type(g::Topology, i::Int) = 1 <= i <= length(g.node_types_labels)
is_edge_type(g::Topology, i::Int) = 1 <= i <= length(g.edge_types_labels)
is_node_type(g::Topology, lab::Symbol) = lab in keys(g.node_types_index)
is_edge_type(g::Topology, lab::Symbol) = lab in keys(g.edge_types_index)
export is_node_type, is_edge_type
