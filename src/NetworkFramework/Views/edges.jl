"Direct view into *dense* web data."
struct DenseEdgeFieldView{d,T} <: AbstractMatrix{T} # d::D.Web (sparse)
    model::Model
    view::N.EdgeView{T}
end
let S = DenseEdgeFieldView
    V.extract(s::S; kw...) = N.to_dense(N.view(s); kw...)
end

"Direct view into *sparse* web data."
struct SparseEdgeFieldView{d,T} <: AbstractSparseMatrix{T,Int} # d::Web (dense)
    model::Model
    view::N.EdgeView{T}
end

let S = SparseEdgeFieldView
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

const EdgeFieldView{d,T} = Union{DenseEdgeFieldView{d,T},SparseEdgeFieldView{d,T}}

function field_view(d::D.EdgeField, m::Model)
    view = N.edges_view(N.network(m), D.webname(d), D.fieldname(d))
    T = eltype(view)
    View = D.is_sparse(d) ? SparseEdgeFieldView : DenseEdgeFieldView
    View{d,T}(m, view)
end

let S = EdgeFieldView
    N.web(s::S) = s |> N.view |> N.web
end

# ==========================================================================================
# Topology mask.

"View into edges topology (a binary masks), read-only."
struct EdgeMaskView{d} <: AbstractSparseMatrix{Bool,Int} # d::D.Web
    model::Model
    web::N.Web # Cache an alias to underlying web.
end

function mask_view(d::D.Web, m::Model)
    web = N.web(N.network(m), D.webname(d))
    EdgeMaskView{d}(m, web)
end

let S = EdgeMaskView
    N.web(s::S) = getfield(s, :web)
    V.extract(s::S) = s |> N.topology |> N.to_mask
    # Duty to AbstractSparseMatrix..?
    SparseArrays.nonzeros(s::S) = ones(eltype(s), s |> N.web |> N.n_edges)
end

# ==========================================================================================
# Common to sparse views.

const SparseEdgeView = Union{SparseEdgeFieldView,EdgeMaskView}
let S = SparseEdgeView
    # Duty to AbstractSparseMatrix..?
    Base.similar(s::S) = spzeros(eltype(s), size(s))
    SparseArrays.nnz(s::S) = s |> N.n_edges
    function SparseArrays.findnz(s::S)
        is, js = map(1:2) do _
            sizehint!(Int[], nnz(s))
        end
        for (i, j) in N.edges(s)
            push!(is, i)
            push!(js, j)
        end
        (is, js, nonzeros(s))
    end
    V.extract(s::S; kw...) = N.to_sparse(N.view(s); kw...)
end

# ==========================================================================================
# Common to all edge views.

const EdgeView{d} = Union{EdgeFieldView{d},EdgeMaskView{d}}
let S = EdgeView
    for fn in [
        D.web, D.webname,
        D.source, D.sourcename,
        D.target, D.targetname,
        D.is_sparse, D.is_dense,
    ]
        eval(quote
            (::$(typeof(fn)))(s::$S) = s |> dispatcher |> $fn
        end)
    end

    N.web(s::S) = N.web(NF.model(s), dispatcher(s))
    N.topology(s::S) = N.web(s).topology
    N.to_index(s::S, a...; k...) = N.to_index(NF.model(s), dispatcher(s), a...; k...)
    N.to_label(s::S, a...; k...) = N.to_label(NF.model(s), dispatcher(s), a...; k...)
    Base.size(s::S) = s |> N.web |> size
    N.n_edges(s::S) = s |> N.topology |> N.n_edges
    N.edges(s::S) = s |> N.topology |> N.edges
    N.is_edge(s::S, i, j) = _is_edge(s, N.to_index(s, i, j)...)
    _is_edge(s::S, i::Int, j::Int) = N.is_edge(N.topology(s), i, j) # Unchecked.
    function N.edge(s::S, i::Ref, j::Ref)
        i, j = N.to_index(s, i, j)
        _is_edge(s, i, j) || return nothing
        tp = N.topology(s)
        N.edge(tp, i, j)
    end
end
