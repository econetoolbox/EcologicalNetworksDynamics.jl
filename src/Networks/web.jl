"""
One web of edges between two nodes classes,
specifying the topology among these nodes
and holding associated data: only vectors whose size match the number of edges.
Information for indexing into the edges is provided by the topology.
"""
struct Web
    name::Symbol
    source::Symbol
    target::Symbol
    topology::Topology
    data::Dict{Symbol,Entry{<:Vector}}
end

"""
Construct without associated data.
"""
Web(name, source, target, topology) = Web(name, source, target, topology, Dict())

"""
Fork web, called when COW-pying the whole network.
"""
function fork(w::Web)
    (; name, source, target, topology, data) = w
    # May reference the same (immutable) topology.
    Web(name, source, target, topology, fork(data))
end

# Visit all entries.
entries(w::Web) = values(w.data)

"""
Number of fields in the web.
"""
n_fields(w::Web) = length(w.data)

# Forward simple requests to topology.
n_edges(w::Web) = n_edges(w.topology)
n_sources(w::Web) = n_sources(w.topology)
n_targets(w::Web) = n_targets(w.topology)
