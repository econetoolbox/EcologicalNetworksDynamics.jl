"""
Direct view into *dense* web data.
"""
struct DenseEdgesFieldView{d,T} <: AbstractMatrix{T} # d::D.Web (sparse)
    model::Model
    view::N.EdgesView{T}
end
let S = DenseEdgesFieldView
    V.extract(s::S; kw...) = N.to_dense(N.view(s); kw...)
end

"""
Direct view into *sparse* web data.
"""
struct SparseEdgesFieldView{d,T} <: AbstractSparseMatrix{T,Int} # d::Web (dense)
    model::Model
    view::N.EdgesView{T}
end

let S = SparseEdgesFieldView
    # Duty to AbstractSparseMatrix..?
    SparseArrays.nonzeros(s::S) = read(collect, N.entry(s))
    SparseArrays.nnz(s::S) = s |> N.n_edges
    function SparseArrays.findnz(s::S)
        is, js = Int[], Int[]
        for (i, j) in N.edges(s)
            push!(is, i)
            push!(js, j)
        end
        (is, js, nonzeros(s))
    end
    V.extract(s::S; kw...) = N.to_sparse(N.view(s); kw...)
end

#-------------------------------------------------------------------------------------------
# Common to dense and sparse.

const EdgesFieldView{d,T} = Union{DenseEdgesFieldView{d,T},SparseEdgesFieldView{d,T}}

function field_view(d::D.EdgeField, m::Model)
    view = N.edges_view(N.network(m), D.web(d), D.field(d))
    T = eltype(view)
    View = D.is_sparse(d) ? SparseEdgesFieldView : DenseEdgesFieldView
    View{d,T}(m, view)
end

let S = EdgesFieldView
    D.web(s::S) = s |> dispatcher |> D.web
    N.web(s::S) = s |> N.view |> N.web
end

# ==========================================================================================
# Topology mask.

"""
View into edges topology (a binary masks), read-only.
"""
struct EdgesMaskView{d} <: AbstractMatrix{Bool} # d::D.Web
    model::Model
    web::N.Web # Cache an alias to underlying web.
end

function mask_view(d::D.Web, m::Model)
    web = N.web(N.network(m), D.web(d))
    EdgesMaskView{d}(m, web)
end

let S = EdgesMaskView
    N.web(s::S) = getfield(s, :web)
    D.web(s::S) = D.web(dispatcher(s))
    Base.getindex(s::S, i::Ref, j::Ref) = N.is_edge(s, i, j)
    Base.setindex!(s::S, _...) = qerr(s, "Cannot mutate edges topology.")
    V.extract(s::S) = s |> N.topology |> N.to_mask
end

# ==========================================================================================
# Common to all edge views.

EdgesView{d} = Union{EdgesFieldView{d},EdgesMaskView{d}}
let S = EdgesView
    N.topology(s::S) = N.web(s).topology
    D.source(s) = N.web(s).source
    D.target(s) = N.web(s).target
    N.source(s::S) = N.class(N.network(s), D.source(s))
    N.target(s::S) = N.class(N.network(s), D.target(s))
    N.source_index(s::S) = N.source_index(N.network(s), D.web(s))
    N.target_index(s::S) = N.target_index(N.network(s), D.web(s))
    Base.size(s::S) = s |> N.web |> size

    N.n_edges(s::S) = s |> N.topology |> N.n_edges
    N.edges(s::S) = s |> N.topology |> N.edges
    N.is_edge(s::S, i, j) = _is_edge(s, to_indices(s, i, j)...)
    _is_edge(s::S, i::Int, j::Int) = N.is_edge(N.topology(s), i, j) # Unchecked.
    function N.edge(s::S, i::Ref, j::Ref)
        i, j = to_indices(s, i, j)
        _is_edge(s, i, j) || return nothing
        top = N.topology(s)
        N.edge(top, i, j)
    end
end
