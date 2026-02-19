(false) && begin # (fix JuliaLS missing refs)
    using EcologicalNetworksDynamics.Networks
    using EcologicalNetworksDynamics.Framework
end

# ==========================================================================================
# Data views.

"""
Direct dense view into nodes class data.
Parametrized by NodeData dispatcher.
"""
struct NodesDataView{nd,T} <: AbstractVector{T}
    model::Model
    view::N.NodesView{T}
end
function N.nodes_view(m::Model, class::Symbol, fieldname::Symbol)
    view = N.nodes_view(value(m), class, fieldname)
    nd = C.NodeData(class, fieldname)
    T = eltype(view)
    NodesDataView{nd,T}(m, view)
end
S = NodesDataView # "Self"
restriction(s::S) = class(s).restriction
Base.size(s::S) = (s |> view |> length,)
Base.getindex(s::S, ref) = getindex(view(s), check_ref(s, ref))
function Base.setindex!(s::S, x, ref)
    ref = check_ref(s, ref)
    x = check_write(s, x, ref)
    setindex!(view(s), x, ref)
end
extract(s::S) = [s[i] for i in eachindex(s)]

#-------------------------------------------------------------------------------------------
"""
View into nodes class data
from the perspective of a superclass,
resulting in incomplete / sparse data.
Parametrized by ExpandedNodesData dispatcher.
"""
struct ExpandedNodesDataView{xnd,T} <: AbstractSparseVector{T,Int}
    model::Model
    view::N.NodesView{T}
end
function N.nodes_view(
    m::Model,
    (class, parent)::Tuple{Symbol,Option{Symbol}},
    fieldname::Symbol,
)
    view = N.nodes_view(value(m), class, fieldname)
    xnd = C.ExpandedNodeData(class, fieldname, parent)
    T = eltype(view)
    ExpandedNodesDataView{xnd,T}(m, view)
end
S = ExpandedNodesDataView # "Self"
C.parent(s::S) = C.parent(dispatcher(s))
restriction(s::S) = N.restriction(network(s), classname(s), parent(s))
Base.size(s::S) = (n_nodes(network(s), parent(s)),)
Base.getindex(s::S, l::Symbol) = getindex(view(s), check_label(s, l))
function Base.setindex!(s::S, x, l::Symbol)
    l = check_label(s, l)
    x = check_write(s, x, l)
    setindex!(view(s), x, l)
end

function Base.getindex(s::S, i::Int)
    i = restrict_index(s, i)
    read(entry(s), getindex, i)
end

function Base.setindex!(s::S, x, i::Int)
    i = restrict_index(s, i)
    x = check_write(s, x, i)
    mutate!(entry(s), setindex!, x, i)
end

function restrict_index(s::S, i::Int)
    check_index(s, i)
    r = restriction(s)
    if !(i in r)
        class = repr(C.class(s).name)
        parent = repr(C.parent(s))
        err(s, "Node $i in $parent is not a node in $class.")
    end
    N.tolocal(i, r)
end

function extract(s::S)
    T = eltype(s)
    n = length(s)
    r = restriction(s)
    res = spzeros(T, n)
    for i in 1:n
        if i in r
            res[i] = s[i]
        end
    end
    res
end

#-------------------------------------------------------------------------------------------
# Common to all nodes data views.

AbstractNodesDataView{d,T} = Union{NodesDataView{d,T},ExpandedNodesDataView{d,T}}
S = AbstractNodesDataView
classname(s::S) = class(dispatcher(s))
N.class(s::S) = s |> view |> class
index(s::S) = class(s).index

"""
Generic checking logic, assuming checked ref.
"""
check_write(s::S, x, ref) =
    if readonly(s)
        err(s, "Values of $(repr(fieldname(s))) are readonly.")
    else
        x = try
            # Dispatch to correct possible check extension.
            d = dispatcher(s)
            C.check_value(d, model(s), x, ref)
        catch e
            e isa C.ValueError || rethrow(e)
            rethrow(WriteError(e, fieldname(s), ref, x))
        end
        x
    end

# ==========================================================================================
# Immutable topology views.

"""
An immutable view into network class label names.
Parametrized by NodeClass dispatcher.
"""
struct NodesNamesView{nc} <: AbstractVector{Symbol}
    # Overkill right now, but keep it for future compat.
    model::Model
    index::N.Index # Cache an underlying class index alias.
end
function nodes_names_view(m::Model, class::Symbol)
    index = N.class(value(m), class).index
    nc = C.NodeClass(class)
    NodesNamesView{nc}(m, index)
end
S = NodesNamesView
index(s::S) = getfield(s, :index)
Base.size(s::S) = (s |> index |> length,)
Base.getindex(s::S, i::Int) = to_label(s, check_index(s, i))
Base.getindex(s::S, l::Symbol) = check_label(s, l) # (not exactly useful but consistent)
Base.setindex!(s::S, _, ::Any) =
    err(s, "Cannot change :$(classname(s)) nodes names after they have been set.")
export nodes_names_view
extract(s::S) = copy(index(s).reverse)

#-------------------------------------------------------------------------------------------
"""
An immutable view into network class restriction mask.
Parametrized by NodeMask dispatcher.
"""
struct NodesMaskView{nm} <: AbstractVector{Bool}
    model::Model
    restriction::N.Restriction
end
function nodes_mask_view(m::Model, (class, parent)::Tuple{Symbol,Option{Symbol}})
    r = N.restriction(value(m), class, parent)
    nm = C.NodeMask(class, parent)
    NodesMaskView{nm}(m, r)
end
S = NodesMaskView
C.parent(s::S) = C.parent(dispatcher(s))
parentclass(s::S) = N.class(network(s), parent(s))
restriction(s::S) = getfield(s, :restriction)
Base.size(s::S) =
    (isnothing(parent(s)) ? n_nodes(network(s)) : length(class(network(s), parent(s))),)
Base.getindex(s::S, i::Int) = check_index(s, i) in restriction(s)
Base.getindex(s::S, l::Symbol) = N.is_label(
    isnothing(parent(s)) ? N.check_label(l, network(s)) : N.check_label(l, parentclass(s)),
    class(s),
)
Base.setindex!(s::S, _, ::Any) =
    err(s, "Cannot change :$(classname(s)) nodes mask after it has been set.")
export nodes_mask_view
function extract(s::S)
    res = spzeros(Bool, length(s))
    for i in s |> restriction |> N.indices
        res[i] = true
    end
    res
end

#-------------------------------------------------------------------------------------------
# Common to topology node views.

NodeTopologyView{C} = Union{NodesNamesView{C},NodesMaskView{C}}
S = NodeTopologyView
classname(::S{C}) where {C} = C
readonly(::S) = C.readonly()
N.class(s::S) = class(network(s), classname(s))

# ==========================================================================================
# Common to all node views.

NodesView{d} = Union{AbstractNodesDataView{d},NodesNamesView{d},NodesMaskView{d}}
S = NodesView
index(s::S) = class(s).index
Base.getindex(s::S) = errnodesdim(s, ())
Base.setindex!(s::S, _) = errnodesdim(s, ())
Base.getindex(s::S, i, j, k...) = errnodesdim(s, (i, j, k...))
Base.setindex!(s::S, _, i, j, k...) = errnodesdim(s, (i, j, k...))
errnodesdim(s, i) = err(
    s,
    "Cannot index into nodes with $(length(i)) dimensions: [$(join_elided(i, ", "))].",
)
check_label(s::S, l::Symbol) = N.check_label(l, index(s), classname(s))
check_ref(s::S, i::Int) = check_index(s, i)
check_ref(s::S, l::Symbol) = check_label(s, l)
check_ref(s::S, x::Any) = err(
    s,
    "Views are indexed with indices (::Int) or labels (::Symbol).
     Cannot index with: $(repr(x)) ::$(typeof(x)).",
)

function check_index(s::S, i::Int)
    n, s = ns(length(s))
    class = repr(classname(s))
    i in 1:n || err(s, "Cannot index with [$i] into a view with $n $class node$s.")
    i
end

# Assuming checked input.
N.to_label(s::S, i::Int) = N.to_label(index(s), i)
N.to_index(s::S, l::Symbol) = N.to_index(index(s), l)
