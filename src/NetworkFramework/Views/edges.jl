"Direct view into *dense* web data."
struct DenseEdgeFieldView{s,T} <: AbstractMatrix{T} # s::S.Web (sparse)
    model::Model
    view::N.EdgeView{T}
end
let V = DenseEdgeFieldView
    VW.extract(v::V; kw...) = N.to_dense(N.view(v); kw...)
end

"Direct view into *sparse* web data."
struct SparseEdgeFieldView{s,T} <: AbstractSparseMatrix{T,Int} # s::Web (dense)
    model::Model
    view::N.EdgeView{T}
end

let V = SparseEdgeFieldView
    # Duty to AbstractSparseMatrix..?
    SparseArrays.nonzeros(v::V) = read(collect, N.entry(v))
    SparseArrays.nnz(v::V) = v |> N.n_edges
    function SparseArrays.findnz(v::V)
        is, js = Int[], Int[]
        for (i, j) in N.edges(v)
            push!(is, i)
            push!(js, j)
        end
        (is, js, nonzeros(v))
    end
    VW.extract(v::V; kw...) = N.to_sparse(N.view(v); kw...)
end

#-------------------------------------------------------------------------------------------
# Common to dense and sparse.

const EdgeFieldView{s,T} = Union{DenseEdgeFieldView{s,T},SparseEdgeFieldView{s,T}}

function field_view(s::SL.EdgeField, m::Model)
    view = N.edges_view(N.network(m), SL.webname(s), SL.fieldname(s))
    T = eltype(view)
    View = SL.is_sparse(s) ? SparseEdgeFieldView : DenseEdgeFieldView
    View{s,T}(m, view)
end

let V = EdgeFieldView
    N.web(v::V) = v |> N.view |> N.web
end

# ==========================================================================================
# Topology mask.

"View into edges topology (a binary masks), read-only."
struct EdgeMaskView{s} <: AbstractSparseMatrix{Bool,Int} # s::S.Web
    model::Model
    web::N.Web # Cache an alias to underlying web.
end

function mask_view(s::SL.Web, m::Model)
    web = N.web(N.network(m), SL.webname(s))
    EdgeMaskView{s}(m, web)
end

let V = EdgeMaskView
    N.web(v::V) = getfield(v, :web)
    VW.extract(v::V) = v |> N.topology |> N.to_mask
    # Duty to AbstractSparseMatrix..?
    SparseArrays.nonzeros(v::V) = ones(eltype(v), v |> N.web |> N.n_edges)
end

# ==========================================================================================
# Common to sparse views.

const SparseEdgeView = Union{SparseEdgeFieldView,EdgeMaskView}
let V = SparseEdgeView
    # Duty to AbstractSparseMatrix..?
    Base.similar(v::V) = spzeros(eltype(v), size(v))
    SparseArrays.nnz(v::V) = v |> N.n_edges
    function SparseArrays.findnz(v::V)
        is, js = map(1:2) do _
            sizehint!(Int[], nnz(v))
        end
        for (i, j) in N.edges(v)
            push!(is, i)
            push!(js, j)
        end
        (is, js, nonzeros(v))
    end
    VW.extract(v::V; kw...) = N.to_sparse(N.view(v); kw...)
end

# ==========================================================================================
# Common to all edge views.

const EdgeView{s} = Union{EdgeFieldView{s},EdgeMaskView{s}}
let V = EdgeView
    for fn in [
        SL.web, SL.webname,
        SL.source, SL.sourcename,
        SL.target, SL.targetname,
        SL.is_sparse, SL.is_dense,
    ]
        eval(quote
            (::$(typeof(fn)))(v::$V) = v |> selector |> $fn
        end)
    end

    N.web(v::V) = N.web(NF.model(v), selector(v))
    N.topology(v::V) = N.web(v).topology
    N.to_index(v::V, a...; k...) = N.to_index(NF.model(v), selector(v), a...; k...)
    N.to_label(v::V, a...; k...) = N.to_label(NF.model(v), selector(v), a...; k...)
    Base.size(v::V) = v |> N.web |> size
    N.n_edges(v::V) = v |> N.topology |> N.n_edges
    N.edges(v::V) = v |> N.topology |> N.edges
    N.is_edge(v::V, i, j) = _is_edge(v, N.to_index(v, i, j)...)
    _is_edge(v::V, i::Int, j::Int) = N.is_edge(N.topology(v), i, j) # Unchecked.
    function N.edge(v::V, i::Ref, j::Ref)
        i, j = N.to_index(v, i, j)
        _is_edge(v, i, j) || return nothing
        tp = N.topology(v)
        N.edge(tp, i, j)
    end
end
