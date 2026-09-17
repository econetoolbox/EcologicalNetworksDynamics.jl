# Standardize incoming edge data to topology + edge vector,
# given a topology or not, adjacency lists etc.
# (inefficient yet, worry about this later if relevant)

module EdgeDataImports

using ..Networks

using SparseArrays
const I = Iterators
disp(x) = repr(MIME("text/plain"), x)

# ==========================================================================================
# Produce edge data vector given an existing topology + data.

function edges_vec(t::FullTopology, m::AbstractMatrix)
    check_dims(t, m)
    collect(I.flatten(eachcol(m)))
end
function edges_vec(t::SparseTopology, m::AbstractSparseMatrix)
    check_topology(t, m)
    [m[i, j] for (i, j) in edges(t)]
end

# Only half the entries are edges in the symmetric cases.
function edges_vec(t::FullSymmetric, m::AbstractMatrix)
    check_dims(t, m)
    collect(I.flatten(col[1:i] for (i, col) in enumerate(eachcol(m))))
end
function edges_vec(t::SparseSymmetric, m::AbstractSparseMatrix)
    check_topology(t, m)
    [m[j, i] for (i, j) in edges(t)] # Pick from upper triangle.
end
export edges_vec

# TODO: accept adjacency lists given an index for source / target?

# ==========================================================================================
# Guards.

struct EdgeImportError <: Exception
    message::String
end
err(m, throw = throw) = throw(EdgeImportError(m))

function check_dims(t::Topology, m::AbstractMatrix)
    exp = n_sources(t), n_targets(t)
    act = size(m)
    exp == act || err("Dimension mismatch: topology $(exp), matrix $(act).")
end

function check_topology(t::T, m::AbstractMatrix) where {T<:Topology}
    check_dims(t, m)
    exp = t
    act = T(m)
    if exp != act
        ne, na = n_edges.((exp, act))
        ne == na || err("Topology mismatch: expected edges: $ne, received: $na.")
        for (e, a) in zip(edges(exp), edges(act))
            e == a || err("Topology mismatch: unexpected edge $a: $(m[a...]).")
        end
    end
end

end
using .EdgeDataImports
export edges_vec
