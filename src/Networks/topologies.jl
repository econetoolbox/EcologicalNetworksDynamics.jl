"""
The topology descripts edges within a web,
and the neighbouring relation among source and target nodes in incident classes.
Source and target classes are only described by their number of nodes.
Edges are ordered so they can be contiguously indexed by a number.
Watch that they are ordered *row-wise*
in the standard '(row, column)' ~ '(source, target)' dimensions ordering,
therefore *not* complying to julia's column-wise matrices convention.

There are various kinds of topologies with different implementations.

Regarding incident classes:

  - Foreign: the two classes differ.
  - Reflexive: source class and target class are the same class.
  - Symmetric: reflexive + edges are undirected ('a' points to 'b' => 'b' points to 'a').

Regarding edges density:

  - Sparse: there are less than n(source) × n(targets) edges (expectedly *much* less).
  - Full: all the n(sources) × n(targets) edges exist.
"""
abstract type Topology end
export Topology

# ==========================================================================================
# Abstract topology interface.

"""
Obtain general nodes counts.
"""
n_targets(::Topology) = throw("unimplemented")
n_sources(::Topology) = throw("unimplemented")
export n_targets, n_sources

"""
Obtain iterable over target neighbours as (target, edge).
"""
targets(::Topology, ::Int) = throw("unimplemented")
target_nodes(g::Topology, s::Int) = I.map(first, targets(g, s))
target_edges(g::Topology, s::Int) = I.map(last, targets(g, s))
n_targets(::Topology, ::Int) = throw("unimplemented")
export targets, target_nodes, target_edges, n_targets

"""
Obtain iterable over source neighbours as (source, edge).
"""
sources(::Topology, ::Int) = throw("unimplemented")
source_nodes(g::Topology, t::Int) = I.map(first, sources(g, t))
source_edges(g::Topology, t::Int) = I.map(last, sources(g, t))
n_sources(::Topology, ::Int) = throw("unimplemented")
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
Obtain an iterable over edges as (source, target), in canonical edge order.
"""
edges(::Topology) = throw("unimplemented")
export edges

"""
Obtain a nested iterable over edges:
first level are sources, second level are their incident targets and edges.
Collecting the two levels yields [(source, [(target, edge), ..]), ..]
Raise flag to skip over sources with no targets.
"""
forward(::Topology; skip = false) = throw("unimplemented")
export forward

"""
Obtain a nested iterable over edges:
first level are targets, second level are their incident sources and edges.
Collecting the two levels yields [(target, [(source, edge), ..]), ..]
Raise flag to skip over targets with no sources.
"""
backward(::Topology; skip = false) = throw("unimplemented")
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
S = SparseForeign # "Self"
targets(s::S, src::Int) = I.map(p -> (first(p), last(p)), s.forward[src])
sources(s::S, tgt::Int) = I.map(p -> (first(p), last(p)), s.backward[tgt])
n_sources(s::S) = length(s.forward)
n_targets(s::S) = length(s.backward)
n_sources(s::S, tgt::Int) = length(s.backward[tgt])
n_targets(s::S, src::Int) = length(s.forward[src])
is_edge(s::S, src::Int, tgt::Int) = haskey(s.forward[src], tgt)
n_edges(s::S) = s.n_edges
edge(s::S, src::Int, tgt::Int) = s.forward[src][tgt]
edges(s::S) = I.flatten(I.map(enumerate(s.forward)) do (src, targets)
    I.map(keys(targets)) do tgt
        (src, tgt)
    end
end)
forward(s::S; skip = false) =
    filter_map(enumerate(s.forward)) do (src, targets)
        (skip && isempty(targets)) ? nothing : Some((src, I.map(targets) do (tgt, edge)
            (tgt, edge)
        end))
    end
backward(s::S; skip = false) =
    filter_map(enumerate(s.backward)) do (tgt, sources)
        (skip && isempty(sources)) ? nothing : Some((tgt, I.map(sources) do (src, edge)
            (src, edge)
        end))
    end

#-------------------------------------------------------------------------------------------
# Construct.

"""
Construct from non-empty entries in a sparse matrix (disregarding values).
"""
function SparseForeign(m::AbstractSparseMatrix)
    n_sources, n_targets = size(m)
    (sources, targets, _) = findnz(m)
    n_edges = length(sources)
    # Restore row-wise ordering.
    o = sortperm(sources)
    sources, targets = sources[o], targets[o]
    D = OrderedDict{Int,Int}
    forward = [D() for _ in 1:n_sources]
    backward = [D() for _ in 1:n_targets]
    for (edge, (source, target)) in enumerate(zip(sources, targets))
        forward[source][target] = edge
        backward[target][source] = edge
    end
    SparseForeign(forward, backward, n_edges)
end

"""
Construct from lit entries in a dense boolean matrix.
"""
function SparseForeign(m::AbstractMatrix{Bool})
    n_sources, n_targets = size(m)
    D = OrderedDict{Int,Int}
    forward = [D() for _ in 1:n_sources]
    backward = [D() for _ in 1:n_targets]
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
    # [node: ({source: edge}, {target: edge})]
    nodes::Vector{Tuple{OrderedDict{Int,Int},OrderedDict{Int,Int}}}
    n_edges::Int
end
export SparseReflexive

#-------------------------------------------------------------------------------------------
# Duties to Topology.
S = SparseReflexive
targets(s::S, src::Int) = I.map(p -> (first(p), last(p)), s.nodes[src][2])
sources(s::S, tgt::Int) = I.map(p -> (first(p), last(p)), s.nodes[tgt][1])
n_sources(s::S) = length(s.nodes)
n_targets(s::S) = n_sources(s)
n_sources(s::S, tgt::Int) = length(s.nodes[tgt][1])
n_targets(s::S, src::Int) = length(s.nodes[src][2])
is_edge(s::S, src::Int, tgt::Int) = haskey(s.nodes[src][2], tgt)
n_edges(s::S) = s.n_edges
edge(s::S, src::Int, tgt::Int) = s.nodes[src][2][tgt]
edges(s::S) = I.flatten(I.map(enumerate(s.nodes)) do (src, neighbours)
    (_, targets) = neighbours
    I.map(keys(targets)) do tgt
        (src, tgt)
    end
end)
forward(s::S; skip = false) =
    filter_map(enumerate(s.nodes)) do (src, (_, targets))
        (skip && isempty(targets)) ? nothing : Some((src, I.map(targets) do (tgt, edge)
            (tgt, edge)
        end))
    end
backward(s::S; skip = false) =
    filter_map(enumerate(s.nodes)) do (tgt, (sources, _))
        (skip && isempty(sources)) ? nothing : Some((tgt, I.map(sources) do (tgt, edge)
            (tgt, edge)
        end))
    end

#-------------------------------------------------------------------------------------------
# Construct.

"""
Construct from non-empty entries in a sparse matrix (disregarding values).
"""
function SparseReflexive(m::AbstractSparseMatrix)
    n_nodes = check_square(m)
    (sources, targets, _) = findnz(m)
    n_edges = length(sources)
    # Restore row-wise ordering.
    o = sortperm(sources)
    sources, targets = sources[o], targets[o]
    D = OrderedDict{Int,Int}
    nodes = [(D(), D()) for _ in 1:n_nodes]
    for (edge, (source, target)) in enumerate(zip(sources, targets))
        nodes[source][2][target] = edge
        nodes[target][1][source] = edge
    end
    SparseReflexive(nodes, n_edges)
end
function check_square(m)
    n_sources, n_targets = size(m)
    n_sources == n_targets ||
        err("Only square matrices can construct reflexive topologies. \
             Received ($n_sources × $n_targets).")
    n_sources
end

"""
Construct from lit entries in a dense boolean matrix.
"""
function SparseReflexive(m::AbstractMatrix{Bool})
    n_nodes = check_square(m)
    D = OrderedDict{Int,Int}
    nodes = [(D(), D()) for _ in 1:n_nodes]
    n_edges = 0
    for source in 1:n_nodes, target in 1:n_nodes
        m[source, target] || continue
        n_edges += 1
        nodes[source][2][target] = n_edges
        nodes[target][1][source] = n_edges
    end
    SparseReflexive(nodes, n_edges)
end
