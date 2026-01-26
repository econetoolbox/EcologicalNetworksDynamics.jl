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
    writeable::Bool
end
S = NodesDataView # "Self"
restriction(v::S) = class(v).restriction
Base.length(v::S) = v |> view |> length
Base.getindex(v::S, ref) = getindex(view(v), ref)
Base.setindex!(v::S, x, ref) =
    writeable(v) ? setindex!(view(v), x, ref) :
    err(v, "Values of $(repr(fieldname(v))) are readonly.")
N.nodes_view(m::Model, class::Symbol, data::Symbol, writeable::Bool) =
    NodesDataView(m, N.nodes_view(value(m), class, data), data, writeable)
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
    writeable::Bool
end
S = ExpandedNodesDataView
parent(v::S) = getfield(v, :parent)
restriction(v::S) = N.restriction(network(v), classname(v), parent(v))
Base.length(v::S) = n_nodes(network(v), parent(v))
Base.getindex(v::S, l::Symbol) = getindex(view(v), l)
Base.setindex!(v::S, x, l::Symbol) = setindex!(view(v), x, l)
N.nodes_view(
    m::Model,
    (class, parent)::Tuple{Symbol,Option{Symbol}},
    data::Symbol,
    writeable::Bool,
) = ExpandedNodesDataView(m, N.nodes_view(value(m), class, data), data, parent, writeable)

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
writeable(v::S) = getfield(v, :writeable)
Base.:(==)(v::S, o::AbstractVector) = extract(v) == o # Inefficient: reconsider if bottleneck.
Base.:(==)(o::AbstractVector, v::S) = v == o

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
Base.setindex!(v::S, _, ::Any) =
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
    parent::Option{Symbol} # TODO: split into 2 types instead?
    restriction::N.Restriction
end
S = NodesMaskView
parent(v::S) = getfield(v, :parent)
parentclass(v::S) = N.class(network(v), parent(v))
restriction(v::S) = getfield(v, :restriction)
Base.length(v::S) =
    isnothing(parent(v)) ? n_nodes(network(v)) : length(class(network(v), parent(v)))
Base.getindex(v::S, i::Int) = check_range(v, i) in restriction(v)
Base.getindex(v::S, l::Symbol) = N.is_label(
    isnothing(parent(v)) ? N.check_label(l, network(v)) : N.check_label(l, parentclass(v)),
    class(v),
)
Base.setindex!(v::S, _, ::Any) =
    err(v, "Cannot change :$(classname(v)) nodes mask after it has been set.")
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
Base.getindex(v::S, i, j, k...) = errnodesdim(v, (i, j, k...))
Base.setindex!(v::S, _, i, j, k...) = errnodesdim(v, (i, j, k...))
errnodesdim(v, i) =
    err(v, "Cannot index into nodes with $(length(i)) dimensions: $(repr(i)).")
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
