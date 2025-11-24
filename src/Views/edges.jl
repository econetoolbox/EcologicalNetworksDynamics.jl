"""
Direct view into web data,
either dense or sparse depending on underlying topology.
"""
struct EdgesView{T}
    model::Model
    view::N.EdgesView{T}
    fieldname::Symbol
end
S = EdgesView
N.web(v::S) = v |> view |> web
source(v::S) = web(v).source
target(v::S) = web(v).target
topology(v::S) = web(v).topology
Base.size(v::S) = v |> topology |> size
Base.length(v::S) = v |> topology |> length
edges_view(m::Model, web::Symbol, data::Symbol) =
    EdgesView(m, N.edges_view(m._value, web, data), data)
inderr(v::S, i) = err(v, "Two indices are required to index into webs. Received: ($i,).")
Base.getindex(v::S, i) = inderr(v, i)
Base.setindex!(v::S, _, i) = inderr(v, i)
Base.getindex(v::S, i, j) = getindex(view(v), (i, j))
Base.setindex!(v::S, x, i, j) = setindex!(view(v), x, (i, j))
export edges_view

# TODO: do we need an ExpandedEdgesView? Maybe refactor components first to figure this.
