(false) && begin # (fix JuliaLS missing refs)
    using EcologicalNetworksDynamics.Networks
    using EcologicalNetworksDynamics.Framework
end

# ==========================================================================================
# Data views.

"""
Direct dense view into nodes class data.
"""
struct NodesDataView{T} <: AbstractVector{T}
    model::Model
    view::N.NodesView{T}
    fieldname::Symbol
    # If writeable, provide a function to check individual values prior to writing.
    # The function feeds from one value of type T
    # and raises a 'String' exception if the value is incorrect.
    check::Option{Function}
end
S = NodesDataView # "Self"
restriction(v::S) = class(v).restriction
Base.size(v::S) = (v |> view |> length,)
Base.getindex(v::S, ref) = getindex(view(v), check_ref(v, ref))
function Base.setindex!(v::S, x, ref)
    ref = check_ref(v, ref)
    x = check_value(v, x, ref)
    setindex!(view(v), x, ref)
end
N.nodes_view(m::Model, class::Symbol, data::Symbol, check::Option{Function}) =
    NodesDataView(m, N.nodes_view(value(m), class, data), data, check)
extract(v::S) = [v[i] for i in eachindex(v)]

"""
View into nodes class data
from the perspective of a superclass,
resulting in incomplete / sparse data.
"""
struct ExpandedNodesDataView{T} <: AbstractSparseVector{T, Int}
    model::Model
    view::N.NodesView{T}
    fieldname::Symbol
    parent::Option{Symbol}
    check::Option{Function}
end
S = ExpandedNodesDataView # "Self"
parent(v::S) = getfield(v, :parent)
restriction(v::S) = N.restriction(network(v), classname(v), parent(v))
Base.size(v::S) = (n_nodes(network(v), parent(v)),)
Base.getindex(v::S, l::Symbol) = getindex(view(v), check_label(v, l))
function Base.setindex!(v::S, x, l::Symbol)
    l = check_label(v, l)
    x = check_value(v, x, l)
    setindex!(view(v), x, l)
end
N.nodes_view(
    m::Model,
    (class, parent)::Tuple{Symbol,Option{Symbol}},
    data::Symbol,
    check::Option{Function},
) = ExpandedNodesDataView(m, N.nodes_view(value(m), class, data), data, parent, check)

function Base.getindex(v::S, i::Int)
    i = restrict_index(v, i)
    read(entry(v), getindex, i)
end

function Base.setindex!(v::S, x, i::Int)
    i = restrict_index(v, i)
    x = check_value(v, x, i)
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
struct NodesNamesView <: AbstractVector{Symbol}
    # Overkill right now, but keep it for future compat.
    model::Model
    classname::Symbol
    index::N.Index # Alias underlying class index.
end
S = NodesNamesView
index(v::S) = getfield(v, :index)
Base.size(v::S) = (v |> index |> length,)
Base.getindex(v::S, i::Int) = index(v).reverse[check_range(v, i)]
Base.getindex(v::S, l::Symbol) = check_label(v, l) # (not exactly useful but consistent)
Base.setindex!(v::S, _, ::Any) =
    err(v, "Cannot change :$(classname(v)) nodes names after they have been set.")
function nodes_names_view(m::Model, class::Symbol)
    c = N.class(value(m), class)
    NodesNamesView(m, class, c.index)
end
export nodes_names_view
extract(v::S) = copy(index(v).reverse)

"""
An immutable view into network class restriction mask.
"""
struct NodesMaskView <: AbstractVector{Bool}
    model::Model
    classname::Symbol
    parent::Option{Symbol} # TODO: split into 2 types instead?
    restriction::N.Restriction
end
S = NodesMaskView
parent(v::S) = getfield(v, :parent)
parentclass(v::S) = N.class(network(v), parent(v))
restriction(v::S) = getfield(v, :restriction)
Base.size(v::S) =
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
    class = repr(classname(v))
    i in 1:n || err(v, "Cannot index with '$i' into a view with $n $class node$s.")
    i
end
Base.getindex(v::S, i, j, k...) = errnodesdim(v, (i, j, k...))
Base.setindex!(v::S, _, i, j, k...) = errnodesdim(v, (i, j, k...))
errnodesdim(v, i) =
    err(v, "Cannot index into nodes with $(length(i)) dimensions: $(repr(i)).")
check_label(v::S, l::Symbol) = N.check_label(l, index(v), classname(v))
check_ref(v::S, i::Int) = check_range(v, i)
check_ref(v::S, l::Symbol) = check_label(v, l)
check_ref(v::S, (s, e)::UnitRange{Int}) = check_range(v, s):check_range(v, e)
