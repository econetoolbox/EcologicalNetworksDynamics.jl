"""
The topology specifies edges within a web,
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
function n_targets end
function n_sources end
export n_targets, n_sources

"""
Obtain iterable over target neighbours as (target, edge).
"""
function targets end
target_nodes(g::Topology, s::Int) = I.map(first, targets(g, s))
target_edges(g::Topology, s::Int) = I.map(last, targets(g, s))
export targets, target_nodes, target_edges, n_targets

"""
Obtain iterable over source neighbours as (source, edge).
"""
function sources end
source_nodes(g::Topology, t::Int) = I.map(first, sources(g, t))
source_edges(g::Topology, t::Int) = I.map(last, sources(g, t))
export sources, source_nodes, source_edges, n_sources

"""
Check whether there is an edge between these two nodes,
assuming they are valid indices.
"""
function is_edge end
export is_edge

"""
Total number of edges in the topology.
"""
function n_edges end
export n_edges

"""
Get edge index, assuming it exists.
"""
function edge end
export edge

"""
Obtain an iterable over edges as (source, target), in canonical edge order.
"""
function edges end
export edges

"""
Obtain a nested iterable over edges:
first level are sources, second level are their incident targets and edges.
Collecting the two levels yields [(source, [(target, edge), ..]), ..].
Raise flag to skip over sources with no targets.
"""
function forward end
export forward

"""
Obtain a nested iterable over edges:
first level are targets, second level are their incident sources and edges.
Collecting the two levels yields [(target, [(source, edge), ..]), ..].
Raise flag to skip over targets with no sources.
"""
function backward end
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
function n_nodes end
export n_nodes

"""
Obtain neighbours in a symmetric topology, neither/both targets or/and sources.
"""
function neighbours end
function n_neighbours end
neighbour_nodes(s::SymmetricTopology, n::Int) = I.map(first, neighbours(s, n))
neighbour_edges(s::SymmetricTopology, n::Int) = I.map(last, neighbours(s, n))
export neighbours, neighbour_nodes, neighbour_edges, n_neighbours

"""
Obtain a nested iterable over neighbours and edges like 'forward' or 'backward'.
Lower 'upper' flag in the symmetric case to skip over duplicate edges
and yield only lower-triangular ones, with (source >= target).
"""
function adjacency end
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
targets(s::S, src::Int) = ((t, e) for (t, e) in s.forward[src])
sources(s::S, tgt::Int) = ((s, e) for (s, e) in s.backward[tgt])
n_sources(s::S) = length(s.forward)
n_targets(s::S) = length(s.backward)
n_sources(s::S, tgt::Int) = length(s.backward[tgt])
n_targets(s::S, src::Int) = length(s.forward[src])
is_edge(s::S, src::Int, tgt::Int) = haskey(s.forward[src], tgt)
n_edges(s::S) = s.n_edges
edge(s::S, src::Int, tgt::Int) = s.forward[src][tgt]
edges(s::S) =
    ((src, tgt) for (src, targets) in enumerate(s.forward) for tgt in keys(targets))
forward(s::S; skip = false) = (
    (src, (tgt, edge) for (tgt, edge) in targets) for
    (src, targets) in enumerate(s.forward) if !(skip && isempty(targets))
)
backward(s::S; skip = false) = (
    (tgt, (src, edge) for (src, edge) in sources) for
    (tgt, sources) in enumerate(s.backward) if !(skip && isempty(sources))
)

#-------------------------------------------------------------------------------------------
# Construct.

"""
Construct from non-empty entries in a sparse matrix
(disregarding values: a `0`-valued entry counts as non-empty).
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
targets(s::S, src::Int) = ((t, e) for (t, e) in s.nodes[src][2])
sources(s::S, tgt::Int) = ((s, e) for (s, e) in s.nodes[tgt][1])
n_sources(s::S) = n_nodes(s)
n_targets(s::S) = n_nodes(s)
n_sources(s::S, tgt::Int) = length(s.nodes[tgt][1])
n_targets(s::S, src::Int) = length(s.nodes[src][2])
is_edge(s::S, src::Int, tgt::Int) = haskey(s.nodes[src][2], tgt)
n_edges(s::S) = s.n_edges
edge(s::S, src::Int, tgt::Int) = s.nodes[src][2][tgt]
edges(s::S) =
    ((src, tgt) for (src, (_, targets)) in enumerate(s.nodes) for (tgt, _) in targets)
forward(s::S; skip = false) = (
    (src, ((tgt, edge) for (tgt, edge) in targets)) for
    (src, (_, targets)) in enumerate(s.nodes) if !(skip && isempty(targets))
)
backward(s::S; skip = false) = (
    (tgt, ((src, edge) for (src, edge) in sources)) for
    (tgt, (sources, _)) in enumerate(s.nodes) if !(skip && isempty(sources))
)

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
targets(s::S, src::Int) = neighbours(s, src)
sources(s::S, tgt::Int) = neighbours(s, tgt)
n_sources(s::S) = n_nodes(s)
n_targets(s::S) = n_nodes(s)
n_sources(s::S, tgt::Int) = n_neighbours(s, tgt)
n_targets(s::S, src::Int) = n_neighbours(s, src)
is_edge(s::S, src::Int, tgt::Int) = haskey(s.nodes[src], tgt) # Accept both directions.
n_edges(s::S) = s.n_edges
edge(s::S, src::Int, tgt::Int) = s.nodes[src][tgt]
edges(s::S) = (
    (src, tgt) for (src, targets) in enumerate(s.nodes) for
    tgt in stopwhen(>(src), keys(targets))
)
forward(s::S; skip = false) = adjacency(s; skip)
backward(s::S; skip = false) = adjacency(s; skip)

# Duties to ReflexiveTopology.
n_nodes(s::S) = length(s.nodes)

# Duties to SymmetricTopology.
neighbours(s::S, src::Int) = ((n, e) for (n, e) in s.nodes[src])
n_neighbours(s::S, n::Int) = length(s.nodes[n])
adjacency(s::S; skip = false, upper = true) = (
    (
        src,
        (
            (ngb, edge) for
            (ngb, edge) in stopwhen(((tgt, _),) -> !upper && tgt > src, neighbours)
        ),
    ) for (src, neighbours) in enumerate(s.nodes) if
    !(skip && (isempty(neighbours) || !upper && first(keys(neighbours)) > src))
)

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

# Property orthogonal to the strict type hierarchy.
const SparseTopology = Union{SparseForeign,SparseReflexive,SparseSymmetric}
export SparseTopology

# ==========================================================================================
# Full topologies.

struct FullForeign <: Topology
    n_sources::Int
    n_targets::Int
end
struct FullReflexive <: ReflexiveTopology
    n_nodes::Int
end
struct FullSymmetric <: SymmetricTopology
    n_nodes::Int
end
export FullForeign, FullReflexive, FullSymmetric

# Density of these topologies makes their interface straightforward and mostly shared.
S = FullForeign
n_sources(s::S) = s.n_sources
n_targets(s::S) = s.n_targets

S = Union{FullReflexive,FullSymmetric}
n_nodes(s::S) = s.n_nodes
n_sources(s::S) = n_nodes(s)
n_targets(s::S) = n_nodes(s)

S = Union{FullForeign,FullReflexive,FullSymmetric}
is_edge(::S, ::Int, ::Int) = true # Assuming correct input.
targets(s::S, src::Int) = ((tgt, edge(s, src, tgt)) for tgt in 1:n_targets(s))
sources(s::S, tgt::Int) = ((src, edge(s, src, tgt)) for src in 1:n_sources(s))
edges(s::S) = ((src, tgt) for src in 1:n_sources(s) for tgt in 1:n_targets(s))
n_sources(s::S, ::Int) = n_sources(s)
n_targets(s::S, ::Int) = n_targets(s)

S = Union{FullForeign,FullReflexive}
edge(s::S, src::Int, tgt::Int) = (src - 1) * n_targets(s) + tgt
n_edges(s::S) = n_sources(s) * n_targets(s)
forward(s::S; skip = false) =
    ((src, ((tgt, edge(s, src, tgt)) for tgt in 1:n_targets(s))) for src in 1:n_sources(s))
backward(s::S; skip = false) =
    ((tgt, ((src, edge(s, src, tgt)) for src in 1:n_sources(s))) for tgt in 1:n_targets(s))

S = FullSymmetric
triangular(n) = (n * (n + 1)) ÷ 2
n_edges(s::S) = triangular(n_nodes(s))
function edge(::S, src::Int, tgt::Int)
    i, j = minmax(src, tgt)
    triangular(j - 1) + i
end
neighbours(s::S, n::Int) = targets(s, n)
n_neighbours(s::S, n::Int) = n_targets(s, n)
adjacency(s::S; skip = false, upper = true) = (
    (src, ((tgt, edge(s, src, tgt)) for tgt in (upper ? (1:n_nodes(s)) : (1:src)))) for
    src in 1:n_nodes(s)
)
forward(s::S; skip = false) = adjacency(s; skip)
backward(s::S; skip = false) = adjacency(s; skip)

# Trivial-construct from matrix dimensions.
FullForeign(m::AbstractMatrix) = FullForeign(size(m)...)
function FullReflexive(m::AbstractMatrix)
    check_square(m)
    FullReflexive(size(m, 1))
end
function FullSymmetric(m::AbstractMatrix)
    check_square(m)
    FullSymmetric(size(m, 1))
end

const FullTopology = Union{FullForeign,FullReflexive,FullSymmetric}
export FullTopology
