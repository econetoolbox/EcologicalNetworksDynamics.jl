"Direct view into *dense* web data."
struct DenseEdgeFieldView{s,T} <: AbstractMatrix{T} # s::S.Web (sparse)
    model::Model
    view::ST.EdgeView{T}
end
let V = DenseEdgeFieldView
    VW.extract(v::V; kw...) = ST.to_dense(ST.view(v); kw...)
end

"Direct view into *sparse* web data."
struct SparseEdgeFieldView{s,T} <: AbstractSparseMatrix{T,Int} # s::Web (dense)
    model::Model
    view::ST.EdgeView{T}
end

let V = SparseEdgeFieldView
    # Duty to AbstractSparseMatrix..?
    SparseArrays.nonzeros(v::V) = read(collect, ST.entry(v))
    SparseArrays.nnz(v::V) = v |> ST.n_edges
    function SparseArrays.findnz(v::V)
        is, js = Int[], Int[]
        for (i, j) in ST.edges(v)
            push!(is, i)
            push!(js, j)
        end
        (is, js, nonzeros(v))
    end
    VW.extract(v::V; kw...) = ST.to_sparse(ST.view(v); kw...)
end

#-------------------------------------------------------------------------------------------
# Common to dense and sparse.

const EdgeFieldView{s,T} = Union{DenseEdgeFieldView{s,T},SparseEdgeFieldView{s,T}}

function field_view(s::SL.EdgeField, m::Model)
    view = ST.edges_view(ST.network(m), SL.webname(s), SL.fieldname(s))
    T = eltype(view)
    View = SL.is_sparse(s) ? SparseEdgeFieldView : DenseEdgeFieldView
    View{s,T}(m, view)
end

let V = EdgeFieldView
    ST.web(v::V) = v |> ST.view |> ST.web
end

# ==========================================================================================
# Topology mask.

"View into edges topology (a binary masks), read-only."
struct EdgeMaskView{s} <: AbstractSparseMatrix{Bool,Int} # s::S.Web
    model::Model
    web::ST.Web # Cache an alias to underlying web.
end

function mask_view(s::SL.Web, m::Model)
    web = ST.web(ST.network(m), SL.webname(s))
    EdgeMaskView{s}(m, web)
end

let V = EdgeMaskView
    ST.web(v::V) = getfield(v, :web)
    VW.extract(v::V) = v |> ST.topology |> ST.to_mask
    # Duty to AbstractSparseMatrix..?
    SparseArrays.nonzeros(v::V) = ones(eltype(v), v |> ST.web |> ST.n_edges)
end

# ==========================================================================================
# Common to sparse views.

const SparseEdgeView = Union{SparseEdgeFieldView,EdgeMaskView}
let V = SparseEdgeView
    # Duty to AbstractSparseMatrix..?
    Base.similar(v::V) = spzeros(eltype(v), size(v))
    SparseArrays.nnz(v::V) = v |> ST.n_edges
    function SparseArrays.findnz(v::V)
        is, js = map(1:2) do _
            sizehint!(Int[], nnz(v))
        end
        for (i, j) in ST.edges(v)
            push!(is, i)
            push!(js, j)
        end
        (is, js, nonzeros(v))
    end
    VW.extract(v::V; kw...) = ST.to_sparse(ST.view(v); kw...)
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

    ST.web(v::V) = ST.web(IT.model(v), selector(v))
    ST.topology(v::V) = ST.web(v).topology
    ST.to_index(v::V, a...; k...) = ST.to_index(IT.model(v), selector(v), a...; k...)
    ST.to_label(v::V, a...; k...) = ST.to_label(IT.model(v), selector(v), a...; k...)
    Base.size(v::V) = v |> ST.web |> size
    ST.n_edges(v::V) = v |> ST.topology |> ST.n_edges
    ST.edges(v::V) = v |> ST.topology |> ST.edges
    ST.is_edge(v::V, i, j) = _is_edge(v, ST.to_index(v, i, j)...)
    _is_edge(v::V, i::Int, j::Int) = ST.is_edge(ST.topology(v), i, j) # Unchecked.
    function ST.edge(v::V, i::Ref, j::Ref)
        i, j = ST.to_index(v, i, j)
        _is_edge(v, i, j) || return nothing
        tp = ST.topology(v)
        ST.edge(tp, i, j)
    end
end
