(false) && using EcologicalNetworksDynamics.Networks # (fix JuliaLS missing refs)

"""
Direct view into web data,
either dense or sparse depending on underlying topology.
"""
struct EdgesDataView{ed,T} <: AbstractMatrix{T}
    model::Model
    view::N.EdgesView{T}
end
function edges_view(m::Model, web::Symbol, data::Symbol)
    view = N.edges_view(value(m), web, data)
    ed = C.EdgeData(web, data)
    T = eltype(view)
    EdgesDataView{ed,T}(m, view)
end
S = EdgesDataView
N.web(v::S) = v |> view |> web
webname(s::S) = N.web(dispatcher(s))
fieldname(s::S) = C.data(dispatcher(s))
Base.getindex(v::S, i, j) = getindex(view(v), (i, j))
Base.setindex!(v::S, x, i, j) = setindex!(view(v), x, (i, j))
extract(v::S; kw...) = N.to_sparse(view(v), kw...)

# TODO: do we need an ExpandedEdgesView? Maybe refactor components first to figure this.

# ==========================================================================================
# Topology mask.

"""
Indirect, immutable view into edges topology (typically masks).
Parametrized with an EdgeWeb dispatcher.
"""
struct EdgesMaskView{ew} <: AbstractMatrix{Bool}
    model::Model
    web::N.Web
end
edges_mask_view(m::Model, web::Symbol) = EdgesMaskView{web}(m, N.web(value(m), web))
S = EdgesMaskView # "Self"
web(v::S) = getfield(v, :web)
webname(s::S) = C.web(dispatcher(s))
topology(v::S) = web(v).topology
Base.getindex(v::S, i::Int, j::Int) = N.is_edge(topology(v), check_range(v, i, j)...)
Base.setindex!(v::S, _, ::Any, ::Any) = err(v, "Cannot mutate edges topology.")
function Base.getindex(v::S, a::Symbol, b::Symbol)
    check_range(v, a, b)
    N.is_edge(topology(v), source_index(v).forward[a], target_index(v).forward[b])
end
export edges_mask_view
extract(v::S) = v |> topology |> N.to_mask

# ==========================================================================================
# Common to all edge views.

EdgesView{d} = Union{EdgesDataView{d},EdgesMaskView{d}}
S = EdgesView
topology(v::S) = web(v).topology
sourcename(v) = web(v).source
targetname(v) = web(v).target
source(v::S) = N.class(network(v), sourcename(v))
target(v::S) = N.class(network(v), targetname(v))
source_index(v::S) = source(v).index
target_index(v::S) = target(v).index
Base.size(v::S) = v |> web |> size
Base.getindex(v::S, i::Ref) = erredgesdim(v, (i,))
Base.setindex!(v::S, _, i::Ref) = erredgesdim(v, (i,))
Base.getindex(v::S, i::Ref, j::Ref, k::Ref, l::Ref...) = erredgesdim(v, (i, j, k, l...))
Base.setindex!(v::S, _, i::Ref, j::Ref, k::Ref, l::Ref...) = erredgesdim(v, (i, j, k, l...))
erredgesdim(v::S, i) = err(
    v,
    "Two indices are required to index into webs. Received $(length(i)): $(repr(i)).",
)

function check_range(v::S, i::Int, j::Int)
    for (i, class) in [(i, source(v)), (j, target(v))]
        n = length(class)
        i in 1:n || err(
            v,
            "Cannot index with $((i, j)) \
             into a web view for $(repr(webname(v))) of size $(size(web(v))).",
        )
    end
    (i, j)
end

function check_range(v::S, a::Symbol, b::Symbol)
    for (side, l, class) in [("source", a, source(v)), ("target", b, target(v))]
        l in keys(class.index.forward) || err(
            v,
            "Cannot index with $(repr((a, b))) \
             into a web view for $(repr(webname(v))) data \
             because $(repr(l)) is not a node label in $side class $(repr(class.name)).",
        )
    end
    (a, b)
end
