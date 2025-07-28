"""
One web of edges between two nodes classes,
specifying the topology among these nodes
and holding associated data: only vectors whose size match the number of edges.
"""
struct Web
    name::Symbol
    topology::Topology
    data::Dict{Symbol,Entry{<:Vector}}
end
# HERE: implement.

"""
Fork web, called when COW-pying the whole network.
"""
function fork(w::Web)
    (;) = w
    Web()
end

entries(::Web) = ()
