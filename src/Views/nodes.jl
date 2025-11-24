"""
Direct dense view into nodes class data.
"""
struct NodesView{T}
    model::Model
    view::N.NodesView{T}
    fieldname::Symbol
end
S = NodesView # "Self"
restriction(v::S) = class(v).restriction
Base.length(v::S) = length(view(v))
Base.getindex(v::S, i) = getindex(view(v), i)
Base.setindex!(v::S, x, i) = setindex!(view(v), x, i)
nodes_view(m::Model, class::Symbol, data::Symbol) =
    NodesView(m, N.nodes_view(m._value, class, data), data)
export nodes_view

"""
View into nodes class data
from the perspective of a superclass,
resulting in incomplete / sparse data.
"""
struct ExpandedNodesView{T}
    model::Model
    view::N.NodesView{T}
    fieldname::Symbol
    parent::Option{Symbol}
end
S = ExpandedNodesView
parent(v::S) = getfield(v, :parent)
restriction(v::S) = N.restriction(network(v), class(v).name, parent(v))
Base.length(v::S) = n_nodes(network(v), parent(v))
nodes_view(m::Model, (class, parent)::Tuple{Symbol,Option{Symbol}}, data::Symbol) =
    ExpandedNodesView(m, N.nodes_view(m._value, class, data), data, parent)
Base.getindex(v::S, l::Symbol) = getindex(view(v), l)
Base.setindex!(v::S, x, l::Symbol) = setindex!(view(v), x, l)

function Base.getindex(v::S, i::Int)
    i = restrict_index(v, i)
    read(entry(v), getindex, i)
end

function Base.setindex!(v::S, x, i::Int)
    i = restrict_index(v, i)
    mutate!(entry(v), setindex!, x, i)
end

function restrict_index(v::S, i::Int)
    n, s = ns(length(v))
    i in 1:n || err(v, "Cannot index with $i for a view with $n node$s.")
    r = restriction(v)
    if !(i in r)
        class = repr(V.class(v).name)
        parent = repr(V.parent(v))
        err(v, "Node $i in $parent is not an node in $class.")
    end
    N.tolocal(i, r)
end

# Interface common to all node views.
AbstractNodesView{T} = Union{NodesView{T},ExpandedNodesView{T}}
S = AbstractNodesView
N.class(v::S) = v |> view |> class
