# Use topology interface to implement various graph algorithms.

"""
Iterate or filter every node without an incoming edge.
"""
sources(t::ReflexiveTopology) = I.filter(n -> is_source(t, n), 1:n_nodes(t))
sources_mask(t::ReflexiveTopology) = I.map(n -> is_source(t, n), 1:n_nodes(t))
is_source(t::ReflexiveTopology, node::Int) = n_sources(t, node) == 0
export sources, sources_mask, is_source

"""
Iterate or filter every node without an outgoing edge.
"""
sinks(t::ReflexiveTopology) = I.filter(n -> is_sink(t, n), 1:n_nodes(t))
sinks_mask(t::ReflexiveTopology) = I.map(n -> is_sink(t, n), 1:n_nodes(t))
is_sink(t::ReflexiveTopology, node::Int) = n_targets(t, node) == 0
export sinks, sinks_mask, is_sink

"""
Iterate or filter every node with incoming edges.
"""
nonsources(t::ReflexiveTopology) = I.filter(n -> !is_source(t, n), 1:n_nodes(t))
nonsources_mask(t::ReflexiveTopology) = I.map(n -> !is_source(t, n), 1:n_nodes(t))
export nonsources, nonsources_mask

"""
Iterate or filter every node with outgoing edges.
"""
nonsinks(t::ReflexiveTopology) = I.filter(n -> !is_sink(t, n), 1:n_nodes(t))
nonsinks_mask(t::ReflexiveTopology) = I.map(n -> !is_sink(t, n), 1:n_nodes(t))
export nonsinks, nonsinks_mask
