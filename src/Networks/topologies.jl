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
    In this *bidirectional* situation: the number of edges
    is the number of conceptual *undirected* edges,
    And their order is the row-wise lower triangular only: (source >= target) pairs.

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
Collecting the two levels yields [(source, [(target, edge), ..]), ..].
Raise flag to skip over sources with no targets.
"""
forward(::Topology; skip = false) = throw("unimplemented")
export forward

"""
Obtain a nested iterable over edges:
first level are targets, second level are their incident sources and edges.
Collecting the two levels yields [(target, [(source, edge), ..]), ..].
Raise flag to skip over targets with no sources.
"""
backward(::Topology; skip = false) = throw("unimplemented")
export backward

#-------------------------------------------------------------------------------------------
# Extend interface for constrained topologies.
"""
A 'square' topology within one class, both source and target of the web.
"""
abstract type ReflexiveTopology <: Topology end
"""
A 'bidirectional' reflexive topology:
if a targets b then b targets a, and this only counts for one edge.
"""
abstract type SymmetricTopology <: ReflexiveTopology end

"""
Obtain the number of nodes in the topology.
"""
n_nodes(::ReflexiveTopology) = throw("unimplemented")
export n_nodes

"""
Obtain neighbours in a symmetric topology, neither/both targets or/and sources.
"""
neighbours(::SymmetricTopology, ::Int) = throw("unimplemented")
neighbours_nodes(::SymmetricTopology, ::Int) = throw("unimplemented")
neighbours_edges(::SymmetricTopology, ::Int) = throw("unimplemented")
n_neighbours(::SymmetricTopology, ::Int) = throw("unimplemented")
export neighbours, neighbour_nodes, neighbour_edges, n_neighbours

"""
Obtain a nested iterable over neighbours and edges like 'forward' or 'backward'.
Lower 'upper' flag to skip over duplicate edges and yield only lower-triangular ones,
with (source >= target).
"""
adjacency(::SymmetricTopology; skip = false, upper = true) = throw("unimplemented")
export adjacency

Map = OrderedDict{Int,Int} # Used by the sparse variants.
vecmap(n::Int) = [Map() for _ in 1:n]

# ==========================================================================================
struct SparseForeign <: Topology
    forward::Vector{Map} # [source: {target: edge}]
    backward::Vector{Map} # [target: {source: edge}]
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
edges(s::S) =
    I.flatmap(enumerate(s.forward)) do (src, targets)
        I.map(keys(targets)) do tgt
            (src, tgt)
        end
    end
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
    (sources, targets, n_edges) = rowwise(m)
    (forward, backward) = vecmap.((n_sources, n_targets))
    for (edge, (source, target)) in enumerate(zip(sources, targets))
        forward[source][target] = edge
        backward[target][source] = edge
    end
    SparseForeign(forward, backward, n_edges)
end
# Extract data from sparse matrix with *row-wise* ordering.
function rowwise(m::AbstractSparseMatrix)
    (sources, targets, _) = findnz(m)
    n_edges = length(sources)
    o = sortperm(sources)
    (sources[o], targets[o], n_edges)
end


"""
Construct from lit entries in a dense boolean matrix.
"""
function SparseForeign(m::AbstractMatrix{Bool})
    n_sources, n_targets = size(m)
    (forward, backward) = vecmap.((n_sources, n_targets))
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
struct SparseReflexive <: ReflexiveTopology
    # [node: ({source: edge}, {target: edge})]
    nodes::Vector{Tuple{Map,Map}}
    n_edges::Int
end
export SparseReflexive

#-------------------------------------------------------------------------------------------
# Duties to Topology.
S = SparseReflexive
targets(s::S, src::Int) = I.map(p -> (first(p), last(p)), s.nodes[src][2])
sources(s::S, tgt::Int) = I.map(p -> (first(p), last(p)), s.nodes[tgt][1])
n_sources(s::S) = n_nodes(s)
n_targets(s::S) = n_nodes(s)
n_sources(s::S, tgt::Int) = length(s.nodes[tgt][1])
n_targets(s::S, src::Int) = length(s.nodes[src][2])
is_edge(s::S, src::Int, tgt::Int) = haskey(s.nodes[src][2], tgt)
n_edges(s::S) = s.n_edges
edge(s::S, src::Int, tgt::Int) = s.nodes[src][2][tgt]
edges(s::S) =
    I.flatmap(enumerate(s.nodes)) do (src, neighbours)
        (_, targets) = neighbours
        I.map(keys(targets)) do tgt
            (src, tgt)
        end
    end
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

# Duties to ReflexiveTopology.
n_nodes(s::S) = length(s.nodes)

#-------------------------------------------------------------------------------------------
# Construct.

"""
Construct from non-empty entries in a sparse matrix (disregarding values).
"""
function SparseReflexive(m::AbstractSparseMatrix)
    n_nodes = check_square(m)
    (sources, targets, n_edges) = rowwise(m)
    nodes = [(Map(), Map()) for _ in 1:n_nodes]
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
    nodes = [(Map(), Map()) for _ in 1:n_nodes]
    n_edges = 0
    for source in 1:n_nodes, target in 1:n_nodes
        m[source, target] || continue
        n_edges += 1
        nodes[source][2][target] = n_edges
        nodes[target][1][source] = n_edges
    end
    SparseReflexive(nodes, n_edges)
end

# ==========================================================================================
struct SparseSymmetric <: SymmetricTopology
    nodes::Vector{Map} # [node: {neighbour: edge}]
    n_edges::Int
end
export SparseSymmetric

#-------------------------------------------------------------------------------------------
# Duties to Topology.
S = SparseSymmetric # "Self"
targets(s::S, src::Int) = I.map(p -> (first(p), last(p)), s.nodes[src])
sources(s::S, tgt::Int) = targets(s, tgt)
n_sources(s::S) = n_nodes(s)
n_targets(s::S) = n_nodes(s)
n_sources(s::S, tgt::Int) = n_neighbours(s, tgt)
n_targets(s::S, src::Int) = n_neighbours(s, src)
is_edge(s::S, src::Int, tgt::Int) = haskey(s.nodes[src], tgt) # Accept both directions.
n_edges(s::S) = s.n_edges
edge(s::S, src::Int, tgt::Int) = s.nodes[src][tgt]
edges(s::S) =
    I.flatmap(enumerate(s.nodes)) do (src, targets)
        I.map(stopwhen(>(src), keys(targets))) do tgt
            (src, tgt)
        end
    end
forward(s::S; skip = false) = adjacency(s; skip)
backward(s::S; skip = false) = adjacency(s; skip)

# Duties to ReflexiveTopology.
n_nodes(s::S) = length(s.nodes)

# Duties to SymmetricTopology.
neighbours(s::S, src::Int) = I.map(p -> (first(p), last(p)), s.nodes[src])
neighbour_nodes(s::S, src::Int) = I.map(first, neighbours(s, src))
neighbour_edges(s::S, src::Int) = I.map(last, neighbours(s, src))
n_neighbours(s::S, n::Int) = length(s.nodes[n])
# Lower the 'upper' flag to only get lower triangle and have every edge yielded only once.
adjacency(s::S; skip = false, upper = true) =
    filter_map(enumerate(s.nodes)) do (src, neighbours)
        (skip && (isempty(neighbours) || !upper && first(keys(neighbours)) > src)) ?
        nothing :
        Some((
            src,
            I.map(stopwhen(((tgt, _),) -> !upper && tgt > src, neighbours)) do (ngb, edge)
                (ngb, edge)
            end,
        ))
    end

#-------------------------------------------------------------------------------------------
# Construct.

"""
Construct from non-empty entries in a lower-triangular sparse matrix
(disregarding values and upper triangle).
"""
function SparseSymmetric(m::AbstractSparseMatrix)
    n_nodes = check_square(m)
    (sources, targets, _) = rowwise(m)
    nodes = vecmap(n_nodes)
    n_edges = 0
    for (source, target) in zip(sources, targets)
        source < target && continue # Dismiss upper triangle.
        n_edges += 1
        nodes[source][target] = n_edges
        nodes[target][source] = n_edges
    end
    SparseSymmetric(nodes, n_edges)
end

"""
Construct from lit entries in a lower-triangular dense boolean matrix
(disregarding upper triangle).
"""
function SparseSymmetric(m::AbstractMatrix{Bool})
    n_nodes = check_square(m)
    nodes = vecmap(n_nodes)
    n_edges = 0
    for source in 1:n_nodes, target in 1:source # Triangular iteration.
        m[source, target] || continue
        n_edges += 1
        nodes[source][target] = n_edges
        nodes[target][source] = n_edges
    end
    SparseSymmetric(nodes, n_edges)
end

# ==========================================================================================
struct FullForeign <: Topology
    n_sources::Int
    n_targets::Int
end
export FullForeign

S = FullForeign # "Self"
n_sources(s::S) = s.n_sources
n_targets(s::S) = s.n_targets
targets(s::S, ::Int) = 1:n_targets(s)
sources(s::S, ::Int) = 1:n_sources(s)
n_sources(s::S, ::Int) = n_sources(s)
n_targets(s::S, ::Int) = n_targets(s)
is_edge(::S, ::Int, ::Int) = true # Assuming correct input.
n_edges(s::S) = n_sources(s) * n_targets(s)
edge(s::S, src::Int, tgt::Int) = (src - 1) * n_targets(s) + tgt
edges(s::S) = ((src, tgt) for src in 1:n_sources(s) for tgt in 1:n_targets(s))
forward(s::S; skip = false) =
    I.map(1:n_sources(s)) do src
        (src, I.map(1:n_targets(s)) do tgt
            (tgt, edge(s, src, tgt))
        end)
    end
backward(s::S; skip = false) =
    I.map(1:n_targets(s)) do tgt
        (tgt, I.map(1:n_sources(s)) do src
            (src, edge(s, src, tgt))
        end)
    end
