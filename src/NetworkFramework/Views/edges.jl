(false) && using EcologicalNetworksDynamics.Networks # (fix JuliaLS missing refs)

"""
Direct view into web data,
either dense or sparse depending on underlying topology.
"""
struct EdgesDataView{d,T} <: AbstractMatrix{T}
    model::Model
    view::N.EdgesView{T}
end
export EdgesDataView
function data_view(m::Model, d::D.EdgeField)
    (web, field) = D.content(d)
    n = N.network(m)
    view = N.edges_view(n, web, field)
    T = eltype(view)
    EdgesDataView{d,T}(m, view)
end
S = EdgesDataView
N.web(s::S) = s |> N.view |> N.web
D.web(s::S) = D.web(dispatcher(s))
D.field(s::S) = D.field(dispatcher(s))
Base.getindex(s::S, i, j) = getindex(N.view(s), check_refs(s, i, j))
Base.setindex!(s::S, x, i, j) = setindex!(N.view(s), x, check_refs(s, i, j))
Base.setindex!(s::S, _) = erredgesdim(s, ())
Base.setindex!(s::S, _, i::Ref) = erredgesdim(s, (i,))
Base.setindex!(s::S, _, i::Ref, j::Ref, k::Ref, l::Ref...) = erredgesdim(s, (i, j, k, l...))
extract(s::S; kw...) = N.to_sparse(N.view(s), kw...)

# TODO: do we need an SparseEdgesView? Maybe refactor components first to figure this.

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
export EdgesMaskView
function mask_view(m::Model, d::D.EdgeWeb)
    web = D.web(d)
    n = N.network(m)
    web = N.web(n, web)
    EdgesMaskView{d}(m, web)
end
S = EdgesMaskView # "Self"
N.web(s::S) = getfield(s, :web)
D.web(s::S) = D.web(dispatcher(s))
Base.getindex(s::S, i::Int, j::Int) = N.is_edge(N.topology(s), check_refs(s, i, j)...)
Base.setindex!(s::S, _...) = err(s, "Cannot mutate edges topology.")
function Base.getindex(s::S, a::Symbol, b::Symbol)
    check_refs(s, a, b)
    t = N.topology(s)
    a = N.source_index(s).forward[a]
    b = N.target_index(s).forward[b]
    N.is_edge(t, a, b)
end
extract(s::S) = s |> N.topology |> N.to_mask

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
Base.getindex(s::S) = erredgesdim(s, ())
Base.getindex(s::S, i::Ref) = erredgesdim(s, (i,))
Base.getindex(s::S, i::Ref, j::Ref, k::Ref, l::Ref...) = erredgesdim(s, (i, j, k, l...))
erredgesdim(s::S, i) = err(
    s,
    "Two indices are required to index into webs. \
     Received $(length(i)): [$(EN.join_elided(i, ", "))].",
)
Base.getindex(s::S, i) = @invoke getindex(s::AbstractMatrix, check_ref(s, i))
function Base.getindex(s::S, i, j)
    i = check_ref(s, i)
    j = check_ref(s, j)
    @invoke getindex(s::AbstractMatrix, i, j)
end


check_refs(s::S, src, tgt) =
    (check_ref(s, src, Val(N.source)), check_ref(s, tgt, Val(N.target)))
check_ref(s, ref, _) = check_ref(s, ref)

function check_ref(s::S, i::Int, ::Val{side}) where {side}
    class = side(s)
    m = class.name
    n = length(class)
    w = D.web(s)
    d = disp_index(i, Val(side))
    y = Symbol(side)
    i in 1:n || err(s, "Cannot index with $d into a web $(repr(w)) with $n $m $y nodes.")
    i
end

function check_ref(s::S, l::Symbol, ::Val{side}) where {side}
    class = side(s)
    m = class.name
    w = D.web(s)
    d = disp_index(l, Val(side))
    y = Symbol(side)
    N.is_label(class.index, l) || err(
        s,
        "Cannot index with $d into a web $(repr(w)) \
         because $(repr(l)) is not a node label in $y class $(repr(m)).",
    )
    l
end
disp_index(ref, ::Val{N.source}) = "[$(repr(ref)), ·]"
disp_index(ref, ::Val{N.target}) = "[·, $(repr(ref))]"
