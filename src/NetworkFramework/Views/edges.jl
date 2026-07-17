"""
Direct view into *dense* web data.
"""
struct DenseEdgesDataView{d,T} <: AbstractMatrix{T}
    model::Model
    view::N.EdgesView{T}
end
S = DenseEdgesDataView # "Self"
extract(s::S; kw...) = N.to_dense(N.view(s); kw...)
Base.getindex(s::S, i, j) = getindex(N.view(s), check_refs(s, i, j))
Base.setindex!(s::S, x, i, j) = setindex!(N.view(s), x, check_refs(s, i, j))

"""
Direct view into *sparse* web data.
"""
struct SparseEdgesDataView{d,T} <: AbstractSparseMatrix{T,Int}
    model::Model
    view::N.EdgesView{T}
end
S = SparseEdgesDataView
extract(s::S; kw...) = N.to_sparse(N.view(s); kw...)

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

function data_view(m::Model, d::D.EdgeField)
    (web, field) = D.content(d)
    n = N.network(m)
    view = N.edges_view(n, web, field)
    T = eltype(view)
    V = D.is_sparse(d) ? SparseEdgesDataView : DenseEdgesDataView
    V{d,T}(m, view)
end

function Base.getindex(s::S, src::Ref, tgt::Ref)
    e = N.edge(s, src, tgt)
    isnothing(e) && return zero(D.type(s))
    read(N.entry(s), getindex, e)
end
function Base.setindex!(s::S, x, src::Ref, tgt::Ref)
    e = N.edge(s, src, tgt)
    if isnothing(e)
        x == zero(D.type(s)) && return
        mutoff(s, src, tgt)
    end
    x = check_write(s, x, src, tgt)
    setindex!(N.view(s), x, e)
end

function mutoff(s::S, src, tgt)
    d = dispatcher(s)
    Web = d |> D.EdgeWeb |> D.CamelCaseSingular
    field = D.field(d)
    err(
        s,
        "$Web [$(repr(src)), $(repr(tgt))] is not an edge \
         so there is no $(repr(field)) to mutate.",
    )
end

#-------------------------------------------------------------------------------------------
# Common to dense and sparse.

const EdgesDataView{d,T} = Union{DenseEdgesDataView{d,T},SparseEdgesDataView{d,T}}
S = EdgesDataView #  "Self"
N.web(s::S) = s |> N.view |> N.web
D.web(s::S) = D.web(dispatcher(s))
D.field(s::S) = D.field(dispatcher(s))
Base.setindex!(s::S, _) = erredgesdim(s, ())
Base.setindex!(s::S, _, i::Ref) = erredgesdim(s, (i,))
Base.setindex!(s::S, _, i::Ref, j::Ref, k::Ref, l::Ref...) = erredgesdim(s, (i, j, k, l...))

# TODO: do we need a SubEdgesView? Maybe refactor components first to figure this.

# ==========================================================================================
# Topology mask.

"""
Indirect, immutable view into edges topology (typically masks).
Parametrized with an EdgeWeb dispatcher.
"""
struct EdgesMaskView{d} <: AbstractMatrix{Bool}
    model::Model
    web::N.Web
end
function mask_view(m::Model, d::D.EdgeWeb)
    web = D.web(d)
    n = N.network(m)
    web = N.web(n, web)
    EdgesMaskView{d}(m, web)
end
S = EdgesMaskView # "Self"
N.web(s::S) = getfield(s, :web)
D.web(s::S) = D.web(dispatcher(s))
Base.getindex(s::S, i::Ref, j::Ref) = N.is_edge(s, i, j)
Base.setindex!(s::S, _...) = err(s, "Cannot mutate edges topology.")
extract(s::S) = s |> N.topology |> N.to_mask

Base.getindex(s::S, i::UnitRange, j::Ref) = [N.is_edge(s, i, j) for i in i]
Base.getindex(s::S, i::Ref, j::UnitRange) = [N.is_edge(s, i, j) for j in j]
Base.getindex(s::S, i::UnitRange, j::UnitRange) = [N.is_edge(s, i, j) for i in i, j in j]

# ==========================================================================================
# Common to all edge views.

EdgesView{d} = Union{EdgesDataView{d},EdgesMaskView{d}}
S = EdgesView
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

Base.getindex(s::S) = erredgesdim(s, ())
Base.getindex(s::S, i) = erredgesdim(s, (i,))
Base.getindex(s::S, i::CartesianIndex) = @invoke getindex(s::AbstractMatrix, i)
Base.getindex(s::S, i, j, k, l...) = erredgesdim(s, (i, j, k, l...))
erredgesdim(s::S, i) = err(
    s,
    "Two indices are required to index into webs. \
     Received $(length(i)): [$(EN.join_elided(i, ", "))].",
)
function Base.getindex(s::S, i::Ref, j::Ref)
    i = check_ref(s, i)
    j = check_ref(s, j)
    @invoke getindex(s::AbstractMatrix, i, j)
end

check_refs(s::S, src, tgt) =
    (check_ref(s, src, Val(N.source)), check_ref(s, tgt, Val(N.target)))
check_ref(s, ref, _) = check_ref(s, ref)
to_indices(s::S, src, tgt) =
    (to_index(s, src, Val(N.source)), to_index(s, tgt, Val(N.target)))

function check_ref(s::S, i::Int, ::Val{side}) where {side}
    class = side(s)
    m = class.name
    n = length(class)
    w = D.web(s)
    y = Symbol(side)
    if !(i in 1:n)
        d = disp_index(i, Val(side))
        err(s, "Cannot index with $d into a $(repr(w)) web with $n $m $y nodes.")
    end
    i
end

function check_ref(s::S, l::Symbol, ::Val{side}) where {side}
    class = side(s)
    m = class.name
    w = D.web(s)
    y = Symbol(side)
    if !N.is_label(class.index, l)
        d = disp_index(l, Val(side))
        err(
            s,
            "Cannot index with $d into this $(repr(w)) web \
             because $(repr(l)) is not a node label in $y class $(repr(m)).",
        )
    end
    l
end
disp_index(ref, ::Val{N.source}) = "[$(repr(ref)), ·]"
disp_index(ref, ::Val{N.target}) = "[·, $(repr(ref))]"

to_index(s::S, i::Int, v::Val{side}) where {side} = check_ref(s, i, v)
function to_index(s::S, l::Symbol, v::Val{side}) where {side}
    check_ref(s, l, v)
    class = side(s)
    N.to_index(class.index, l)
end
to_index(s::S, r::UnitRange, v::Val) = to_index(s, first(r), v):to_index(s, last(r), v)

const Index = Union{Ref,UnitRange}
Base.getindex(s::S, src::Index, tgt::Index) =
    D.is_sparse(dispatcher(s)) ? slice_sparse(s, src, tgt) : slice_dense(s, src, tgt)

Base.getindex(s::S, src, tgt) = check_ref.((s,), (src, tgt)) # (to trigger type error)

slice_dense(s::S, src::UnitRange, tgt::Ref) = [s[i, tgt] for i in src]
slice_dense(s::S, src::Ref, tgt::UnitRange) = [s[src, j] for j in tgt]
slice_dense(s::S, src::UnitRange, tgt::UnitRange) = [s[i, j] for j in tgt, i in src]

function slice_sparse(s::S, src::UnitRange, tgt::Ref)
    T = eltype(s)
    res = spzeros(T, length(src))
    for i in src
        N.is_edge(s, i, tgt) || continue
        res[i-first(src)+1] = s[i, tgt]
    end
    res
end
function slice_sparse(s::S, src::Ref, tgt::UnitRange)
    T = eltype(s)
    res = spzeros(T, length(tgt))
    for j in tgt
        N.is_edge(s, src, j) || continue
        res[j-first(tgt)+1] = s[src, j]
    end
    res
end
function slice_sparse(s::S, src::UnitRange, tgt::UnitRange)
    T = eltype(s)
    res = spzeros(T, (length(src), length(tgt)))
    for j in tgt, i in src
        N.is_edge(s, i, j) || continue
        res[i-first(src)+1, j-first(tgt)+1] = s[i, j]
    end
    res
end
