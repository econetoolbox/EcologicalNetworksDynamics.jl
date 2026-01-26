# Extract regular data from an edges view.

"""
Obtain a copy of the underlying vector.
The obtained size and order correspond to the standard edges ordering.
"""
to_vec(v::EdgesView) = read(collect, v)
export to_vec

"""
Obtain values under a dense matrix form,
specifying what to use in entries corresponding to no edge (defaults to `zero(T)`).
"""
function to_dense(t::Topology, v::Vector; empty = Unspecified)
    if empty === Unspecified
        empty = zero(eltype(v))
    end
    [
        is_edge(t, i, j) ? v[edge(t, i, j)] : empty for i in 1:n_sources(t),
        j in 1:n_targets(t)
    ]
end
struct Unspecified end
to_dense(v::EdgesView; kw...) = read(r -> to_dense(web(v).topology, r, kw...), v)
export to_dense

"""
Obtain values under a sparse matrix form.
"""
function to_sparse(t::Topology, v::Vector)
    res = spzeros(eltype(v), n_sources(t), n_targets(t))
    for ((i, j), val) in zip(edges(t), v)
        push_edges!(res, t, i, j, val)
    end
    res
end
push_edges!(res, ::Topology, i, j, val) = res[i, j] = val
function push_edges!(res, t::SymmetricTopology, i, j, val)
    @invoke push_edges!(res, t::Topology, i, j, val)
    @invoke push_edges!(res, t::Topology, j, i, val) # Also fill upper triangle.
end
to_sparse(v::EdgesView; kwargs...) = read(r -> to_sparse(web(v).topology, r), v)
export to_sparse

"""
Obtain a matrix mask (binary sparse matrix).
"""
function to_mask(t::Topology)
    res = spzeros(Bool, n_sources(t), n_targets(t))
    for (i, j) in edges(t)
        res[i, j] = true
    end
    res
end
function to_mask(t::SymmetricTopology)
    res = spzeros(Bool, n_sources(t), n_targets(t))
    for (i, j) in edges(t)
        res[i, j] = true
        res[j, i] = true
    end
    res
end
export to_mask
