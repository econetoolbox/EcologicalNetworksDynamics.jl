(false) && begin # (fix JuliaLS missing refs)
    using EcologicalNetworksDynamics.Networks
    using EcologicalNetworksDynamics.Framework
end

# ==========================================================================================
# Data views.

"""
Direct dense view into nodes class data.
"""
struct NodesDataView{T}
    model::Model
    view::N.NodesView{T}
    fieldname::Symbol
end
S = NodesDataView # "Self"
restriction(v::S) = class(v).restriction
Base.length(v::S) = v |> view |> length
Base.getindex(v::S, r::Ref) = getindex(view(v), r)
Base.setindex!(v::S, x, r::Ref) = setindex!(view(v), x, r)
nodes_view(m::Model, class::Symbol, data::Symbol) =
    NodesDataView(m, N.nodes_view(value(m), class, data), data)
extract(v::S) = [v[i] for i in 1:length(v)]

"""
View into nodes class data
from the perspective of a superclass,
resulting in incomplete / sparse data.
"""
struct ExpandedNodesDataView{T}
    model::Model
    view::N.NodesView{T}
    fieldname::Symbol
    parent::Option{Symbol}
end
S = ExpandedNodesDataView
parent(v::S) = getfield(v, :parent)
restriction(v::S) = N.restriction(network(v), classname(v), parent(v))
Base.length(v::S) = n_nodes(network(v), parent(v))
Base.getindex(v::S, l::Symbol) = getindex(view(v), l)
Base.setindex!(v::S, x, l::Symbol) = setindex!(view(v), x, l)
nodes_view(m::Model, (class, parent)::Tuple{Symbol,Option{Symbol}}, data::Symbol) =
    ExpandedNodesDataView(m, N.nodes_view(value(m), class, data), data, parent)

function Base.getindex(v::S, i::Int)
    i = restrict_index(v, i)
    read(entry(v), getindex, i)
end

function Base.setindex!(v::S, x, i::Int)
    i = restrict_index(v, i)
    mutate!(entry(v), setindex!, x, i)
end

function restrict_index(v::S, i::Int)
    check_range(v, i)
    r = restriction(v)
    if !(i in r)
        class = repr(V.class(v).name)
        parent = repr(V.parent(v))
        err(v, "Node $i in $parent is not a node in $class.")
    end
    N.tolocal(i, r)
end

function extract(v::S)
    T = eltype(v)
    n = length(v)
    r = restriction(v)
    res = spzeros(T, n)
    for i in 1:n
        if i in r
            res[i] = v[i]
        end
    end
    res
end

#-------------------------------------------------------------------------------------------
# Common to all nodes data views.

AbstractNodesDataView{T} = Union{NodesDataView{T},ExpandedNodesDataView{T}}
S = AbstractNodesDataView
N.class(v::S) = v |> view |> class
classname(v::S) = class(v).name

# ==========================================================================================
# Special-cased, immutable topology views.

"""
An immutable view into network class label names.
"""
struct NodesNamesView
    # Overkill right now, but keep it for future compat.
    model::Model
    classname::Symbol
    index::N.Index # Alias underlying class index.
end
S = NodesNamesView
index(v::S) = getfield(v, :index)
Base.length(v::S) = v |> index |> length
Base.getindex(v::S, i::Int) = index(v).reverse[check_range(v, i)]
Base.getindex(v::S, l::Symbol) = check_label(v, l) # (not exactly useful but consistent)
Base.setindex!(v::S, ::Int) =
    err(v, "Cannot change :$(classname(v)) nodes names after they have been set.")
function nodes_names_view(m::Model, class::Symbol)
    c = N.class(value(m), class)
    NodesNamesView(m, class, c.index)
end
export nodes_names_view
Base.eltype(::Type{S}) = Symbol
extract(v::S) = copy(index(v).reverse)

"""
An immutable view into network class restriction mask.
"""
struct NodesMaskView
    model::Model
    classname::Symbol
    parent::Option{Symbol}
    restriction::N.Restriction
end
S = NodesMaskView
parent(v::S) = getfield(v, :parent)
restriction(v::S) = getfield(v, :restriction)
Base.length(v::S) =
    isnothing(parent(v)) ? length(network(v).index) : length(class(network(v), parent(v)))
Base.getindex(v::S, i::Int) = check_range(v, i) in restriction(v)
Base.setindex!(v::S, ::Int) = err(v, "Cannot change :$(classname(v)) nodes mask.")
nodes_mask_view(m::Model, (class, parent)::Tuple{Symbol,Option{Symbol}}) =
    NodesMaskView(m, class, parent, N.restriction(value(m), class, parent))
export nodes_mask_view
function extract(v::S)
    res = spzeros(Bool, length(v))
    for i in v |> restriction |> N.indices
        res[i] = true
    end
    res
end
Base.eltype(::Type{S}) = Bool

#-------------------------------------------------------------------------------------------
# Common to topology node views.

NodeTopologyView = Union{NodesNamesView,NodesMaskView}
S = NodeTopologyView
classname(v::S) = getfield(v, :classname)
N.class(v::S) = class(network(v), classname(v))

# ==========================================================================================
# Common to all node views.

NodesView = Union{AbstractNodesDataView,NodesNamesView,NodesMaskView}
S = NodesView
index(v::S) = class(v).index
function check_range(v::S, i::Int)
    n, s = ns(length(v))
    nname = repr(classname(v))
    i in 1:n || err(v, "Cannot index with '$i' into a view with '$n' $nname node$s.")
    i
end
check_label(v::S, l::Symbol) = N.check_label(l, index(v), classname(v))
# TODO: generic iteration like this must be awfully inefficient
# because of all underlying checking churn.
# Specialize? But is there any way to work around it for the data views?
Base.iterate(v::S) = length(v) > 0 ? (v[1], 1) : nothing
Base.iterate(v::S, i::Int) = length(v) > i ? (v[i+1], i + 1) : nothing
function Base.:(==)(a::S, b::AbstractVector)
    length(a) == length(b) || return false
    for (a, b) in zip(a, b)
        a == b || return false
    end
    true
end
