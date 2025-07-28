"""
The topology descripts edges within a web,
and the neighbouring relation among source and target nodes in incident classes.
Source and target classes are only described by their number of nodes.
Edges are implicitly ordered so they can be contiguously indexed by a number.
Watch that they are ordered *row-wise*
in the standard '(row, column)' ~ '(source, target)' dimensions ordering,
therefore *not* complying to julia's column-wise matrices convention.

There are various kinds of topologies with different implementations.

Regarding incident classes:

  - Foreign: the two classes differ.
  - Reflexive: source class and target class are the same class.
  - Symmetric: reflexive + edges are undirected ('a' points to 'b' => 'b' points to 'a').

Regarding edges density:

  - Sparse: there are less than n(source) × n(targets) edges.
  - Full: all the n(sources) × n(targets) edges exist.
"""
abstract type Topology end
export Topology

"""
Obtain iterator over target neighbours as (target, edge).
"""
targets(::Topology, ::Int) = throw("unimplemented")
target_nodes(g::Topology, s::Int) = I.map(first, targets(g, s))
target_edges(g::Topology, s::Int) = I.map(last, targets(g, s))
n_targets(::Topology) = throw("unimplemented")
export targets, target_nodes, target_edges, n_targets

"""
Obtain iterator over target neighbours as (source, edge).
"""
sources(::Topology, ::Int) = throw("unimplemented")
source_nodes(g::Topology, t::Int) = I.map(first, sources(g, t))
source_edges(g::Topology, t::Int) = I.map(last, sources(g, t))
n_sources(::Topology) = throw("unimplemented")
export sources, source_nodes, source_edges, n_sources

"""
Check whether there is an edge between these two nodes,
assuming they are valid indices.
"""
is_edge(::Topology, ::Int, ::Int) = throw("unimplemented")
export is_edge

"""
Total number of edges in the topology.
"""
n_edges(::Topology) = throw("unimplemented")
export n_edges

"""
Get edge index, assuming it exists.
"""
edge(::Topology, ::Int, ::Int) = throw("unimplemented")
export edge

"""
Obtain an iterator over edges as (source, target), in canonical edge order.
"""
edges(::Topology) = throw("unimplemented")
export edges

"""
Obtain a nested iterator over edges:
first level are sources, second level are their (target, edge).
Raise flag to skip over sources with no targets.
"""
forward(::Topology; skip = true) = throw("unimplemented")
export forward

"""
Obtain a nested iterator over edges:
first level are targets, second level are their (source, edge).
Raise flag to skip over targets with no sources.
"""
backward(::Topology; skip = true) = throw("unimplemented")
export backward

# ==========================================================================================
struct SparseForeign <: Topology
    forward::Vector{OrderedDict{Int,Int}} # [source: {target: edge}]
    backward::Vector{OrderedDict{Int,Int}} # [target: {source: edge}]
    n_edges::Int
end
export SparseForeign

#-------------------------------------------------------------------------------------------
# Duties to Topology.
targets(sf::SparseForeign, src::Int) = I.map(p -> (first(p), last(p)), sf.forward[src])
sources(sf::SparseForeign, tgt::Int) = I.map(p -> (first(p), last(p)), sf.backward[tgt])
n_sources(sf::SparseForeign) = length(sf.forward)
n_targets(sf::SparseForeign) = length(sf.backward)
is_edge(sf::SparseForeign, src::Int, tgt::Int) = haskey(sf.forward[src], tgt)
n_edges(sf::SparseForeign) = sf.n_edges
edge(sf::SparseForeign, src::Int, tgt::Int) = sf.forward[src][tgt]
edges(sf::SparseForeign) = I.flatten(I.map(enumerate(sf.forward)) do (src, targets)
    I.map(keys(targets)) do tgt
        (src, tgt)
    end
end)
forward(sf::SparseForeign; skip = true) =
    filter_map(enumerate(sf.forward)) do (src, targets)
        (skip && isempty(targets)) ? nothing : Some((src, I.map(targets) do (tgt, edge)
            (tgt, edge)
        end))
    end
backward(sf::SparseForeign; skip = true) =
    filter_map(enumerate(sf.backward)) do (tgt, sources)
        (skip && isempty(sources)) ? nothing : Some((tgt, I.map(sources) do (src, edge)
            (src, edge)
        end))
    end

#-------------------------------------------------------------------------------------------
# Construct.

# From nonempty entries in a sparse matrix (disregarding values).
function SparseForeign(m::AbstractSparseMatrix)
    n_sources, n_targets = size(m)
    (sources, targets, _) = findnz(m)
    n_edges = length(sources)
    # Restore row-wise ordering.
    o = sortperm(sources)
    sources, targets = sources[o], targets[o]
    forward = [OrderedDict{Int,Int}() for _ in 1:n_sources]
    backward = [OrderedDict{Int,Int}() for _ in 1:n_targets]
    for (edge, (source, target)) in enumerate(zip(sources, targets))
        forward[source][target] = edge
        backward[target][source] = edge
    end
    SparseForeign(forward, backward, n_edges)
end

# From lit entries in a dense boolean matrix.
function SparseForeign(m::AbstractMatrix{Bool})
    n_sources, n_targets = size(m)
    forward = [OrderedDict{Int,Int}() for _ in 1:n_sources]
    backward = [OrderedDict{Int,Int}() for _ in 1:n_targets]
    n_edges = 0
    for source in 1:n_sources, target in 1:n_targets
        m[source, target] || continue
        n_edges += 1
        forward[source][target] = n_edges
        backward[target][source] = n_edges
    end
    SparseForeign(forward, backward, n_edges)
end

# ==========================================================================================
struct SparseReflexive <: Topology
    # HERE: implement.
end
export SparseReflexive
