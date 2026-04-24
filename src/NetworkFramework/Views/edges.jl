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
function edges_view(m::Model, d::D.EdgeField)
    (web, field) = D.content(d)
    n = NF.network(m)
    view = N.edges_view(n, web, field)
    T = eltype(view)
    EdgesDataView{d,T}(m, view)
end
S = EdgesDataView
N.web(s::S) = s |> view |> web
webname(s::S) = N.web(dispatcher(s))
fieldname(s::S) = D.field(dispatcher(s))
Base.getindex(s::S, i, j) = getindex(view(s), check_refs(s, i, j))
Base.setindex!(s::S, x, i, j) = setindex!(view(s), x, check_refs(s, i, j))
Base.setindex!(s::S, _) = erredgesdim(s, ())
Base.setindex!(s::S, _, i::Ref) = erredgesdim(s, (i,))
Base.setindex!(s::S, _, i::Ref, j::Ref, k::Ref, l::Ref...) = erredgesdim(s, (i, j, k, l...))
extract(s::S; kw...) = N.to_sparse(view(s), kw...)

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
function edges_mask_view(m::Model, d::D.EdgeWeb)
    web = D.web(d)
    n = NF.network(m)
    web = N.web(n, web)
    EdgesMaskView{d}(m, web)
end
S = EdgesMaskView # "Self"
web(s::S) = getfield(s, :web)
webname(s::S) = D.web(dispatcher(s))
topology(s::S) = web(s).topology
Base.getindex(s::S, i::Int, j::Int) = N.is_edge(topology(s), check_refs(s, i, j)...)
Base.setindex!(s::S, _...) = err(s, "Cannot mutate edges topology.")
function Base.getindex(s::S, a::Symbol, b::Symbol)
    check_refs(s, a, b)
    t = topology(s)
    a = source_index(s).forward[a]
    b = target_index(s).forward[b]
    N.is_edge(t, a, b)
end
export edges_mask_view
extract(s::S) = s |> topology |> N.to_mask

# ==========================================================================================
# Common to all edge views.

EdgesView{d} = Union{EdgesDataView{d},EdgesMaskView{d}}
S = EdgesView
topology(s::S) = web(s).topology
sourcename(s) = web(s).source
targetname(s) = web(s).target
source(s::S) = N.class(network(s), sourcename(s))
target(s::S) = N.class(network(s), targetname(s))
source_index(s::S) = source(s).index
target_index(s::S) = target(s).index
Base.size(s::S) = s |> web |> size
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
    (check_ref(s, src, Val(source)), check_ref(s, tgt, Val(target)))
check_ref(s, ref, _) = check_ref(s, ref)

function check_ref(s::S, i::Int, ::Val{side}) where {side}
    class = side(s)
    m = class.name
    n = length(class)
    w = webname(s)
    d = disp_index(i, Val(side))
    y = Symbol(side)
    i in 1:n || err(s, "Cannot index with $d into a web $(repr(w)) with $n $m $y nodes.")
    i
end

function check_ref(s::S, l::Symbol, ::Val{side}) where {side}
    class = side(s)
    m = class.name
    w = webname(s)
    d = disp_index(l, Val(side))
    y = Symbol(side)
    N.is_label(class.index, l) || err(
        s,
        "Cannot index with $d into a web $(repr(w)) \
         because $(repr(l)) is not a node label in $y class $(repr(m)).",
    )
    l
end
disp_index(ref, ::Val{target}) = "[·, $(repr(ref))]"
disp_index(ref, ::Val{source}) = "[$(repr(ref)), ·]"
