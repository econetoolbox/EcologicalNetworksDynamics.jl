# Build over the Unchecked module and checking functions
# to expose checked queries.

const imap = Iterators.map
idmap(x) = imap(identity, x) # Useful to not leak refs to private collections.

# Information about types.
n_node_types(top::Topology) = length(top.node_types_labels)
n_edge_types(top::Topology) = length(top.edge_types_labels)
export n_node_types, n_edge_types

_node_types(top::Topology) = top.node_types_labels
_edge_types(top::Topology) = top.edge_types_labels
node_types(top::Topology) = idmap(_node_types(top))
edge_types(top::Topology) = idmap(_edge_types(top))
export node_types, edge_types

is_node_type(top::Topology, i::Int) = 1 <= i <= length(top.node_types_labels)
is_edge_type(top::Topology, i::Int) = 1 <= i <= length(top.edge_types_labels)
is_node_type(top::Topology, lab::Symbol) = lab in keys(top.node_types_index)
is_edge_type(top::Topology, lab::Symbol) = lab in keys(top.edge_types_index)
export is_node_type, is_edge_type