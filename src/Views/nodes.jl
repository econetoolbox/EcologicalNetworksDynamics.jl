(false) && begin # (fix JuliaLS missing refs)
    using EcologicalNetworksDynamics.Networks
    using EcologicalNetworksDynamics.Framework
end

# ==========================================================================================
# Data views.

"""
Direct dense view into nodes class data.
"""
struct NodesDataView{CF,T} <: AbstractVector{T} # CF: (class, field)
    model::Model
    view::N.NodesView{T}
end
function N.nodes_view(m::Model, class::Symbol, fieldname::Symbol)
    view = N.nodes_view(value(m), class, fieldname)
    CF = (class, fieldname)
    T = eltype(view)
    NodesDataView{CF,T}(m, view)
end
S = NodesDataView # "Self"
restriction(v::S) = class(v).restriction
Base.size(v::S) = (v |> view |> length,)
Base.getindex(v::S, ref) = getindex(view(v), check_ref(v, ref))
function Base.setindex!(v::S, x, ref)
    ref = check_ref(v, ref)
    x = check_write(v, x, ref)
    setindex!(view(v), x, ref)
end
extract(v::S) = [v[i] for i in eachindex(v)]

"""
View into nodes class data
from the perspective of a superclass,
resulting in incomplete / sparse data.
"""
struct ExpandedNodesDataView{CF,P,T} <: AbstractSparseVector{T,Int} # P: parent::Union{Nothing,Symbol}
    model::Model
    view::N.NodesView{T}
end
function N.nodes_view(
    m::Model,
    (class, parent)::Tuple{Symbol,Option{Symbol}},
    fieldname::Symbol,
)
    view = N.nodes_view(value(m), class, fieldname)
    CF = (class, fieldname)
    P = parent
    T = eltype(view)
    ExpandedNodesDataView{CF,P,T}(m, view)
end
S = ExpandedNodesDataView # "Self"
parent(::S{CF,P}) where {CF,P} = P
restriction(v::S) = N.restriction(network(v), classname(v), parent(v))
Base.size(v::S) = (n_nodes(network(v), parent(v)),)
Base.getindex(v::S, l::Symbol) = getindex(view(v), check_label(v, l))
function Base.setindex!(v::S, x, l::Symbol)
    l = check_label(v, l)
    x = check_write(v, x, l)
    setindex!(view(v), x, l)
end

function Base.getindex(v::S, i::Int)
    i = restrict_index(v, i)
    read(entry(v), getindex, i)
end

function Base.setindex!(v::S, x, i::Int)
    i = restrict_index(v, i)
    x = check_write(v, x, i)
    mutate!(entry(v), setindex!, x, i)
end

function restrict_index(v::S, i::Int)
    check_index(v, i)
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

AbstractNodesDataView{CF,T} = Union{NodesDataView{CF,T},ExpandedNodesDataView{CF,T}}
S = AbstractNodesDataView
classfield(::S{CF}) where {CF} = CF
classname(v::S) = first(classfield(v))
N.class(v::S) = v |> view |> class
index(v::S) = class(v).index

"""
Extension point to check and convert individual values
prior to writing them the given index.
Specialize by specifying Val{CF} argument.
Raise with `valerr("simple message")` if anything is incorrect
to obtain a contextualized error.
"""
check_value(v::S, value, ref::Ref, model::Model) = value # Nothing to check a priori.
# User either overrides for index or label, we provide adequate conversion.
check_value(v::S, x, i::Int) = check_value(v, x, to_label(v, i))
check_value(v::S, x, l::Symbol) = check_value(v, x, to_index(v, l))

"""
Generic checking logic, assuming checked ref.
"""
check_write(v::S, x, ref) =
    if readonly(v)
        err(v, "Values of $(repr(fieldname(v))) are readonly.")
    else
        x = try
            CF = classfield(v)
            check_value(Val(CF), x, ref)
        catch e
            e isa ValueError || rethrow(e)
            rethrow(WriteError(e, fieldname(v), ref, x))
        end
        x
    end

# ==========================================================================================
# Immutable topology views.

"""
An immutable view into network class label names.
"""
struct NodesNamesView{C} <: AbstractVector{Symbol}
    # Overkill right now, but keep it for future compat.
    model::Model
    index::N.Index # Cache an underlying class index alias.
end
function nodes_names_view(m::Model, class::Symbol)
    index = N.class(value(m), class).index
    C = class
    NodesNamesView{C}(m, index)
end
S = NodesNamesView
index(v::S) = getfield(v, :index)
Base.size(v::S) = (v |> index |> length,)
Base.getindex(v::S, i::Int) = to_label(v, check_index(v, i))
Base.getindex(v::S, l::Symbol) = check_label(v, l) # (not exactly useful but consistent)
Base.setindex!(v::S, _, ::Any) =
    err(v, "Cannot change :$(classname(v)) nodes names after they have been set.")
export nodes_names_view
extract(v::S) = copy(index(v).reverse)

"""
An immutable view into network class restriction mask.
"""
struct NodesMaskView{C,P} <: AbstractVector{Bool} # P: parent::Union{Nothing,Symbol}
    model::Model
    restriction::N.Restriction
end
function nodes_mask_view(m::Model, (class, parent)::Tuple{Symbol,Option{Symbol}})
    r = N.restriction(value(m), class, parent)
    C, P = class, parent
    NodesMaskView{C,P}(m, r)
end
S = NodesMaskView
parent(::S{C,P}) where {C,P} = P
parentclass(v::S) = N.class(network(v), parent(v))
restriction(v::S) = getfield(v, :restriction)
Base.size(v::S) =
    (isnothing(parent(v)) ? n_nodes(network(v)) : length(class(network(v), parent(v))),)
Base.getindex(v::S, i::Int) = check_index(v, i) in restriction(v)
Base.getindex(v::S, l::Symbol) = N.is_label(
    isnothing(parent(v)) ? N.check_label(l, network(v)) : N.check_label(l, parentclass(v)),
    class(v),
)
Base.setindex!(v::S, _, ::Any) =
    err(v, "Cannot change :$(classname(v)) nodes mask after it has been set.")
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

NodeTopologyView{C} = Union{NodesNamesView{C},NodesMaskView{C}}
S = NodeTopologyView
classname(::S{C}) where {C} = C
N.class(v::S) = class(network(v), classname(v))

# ==========================================================================================
# Common to all node views.

NodesView = Union{AbstractNodesDataView,NodesNamesView,NodesMaskView}
S = NodesView
index(v::S) = class(v).index
Base.getindex(v::S) = errnodesdim(v, ())
Base.setindex!(v::S, _) = errnodesdim(v, ())
Base.getindex(v::S, i, j, k...) = errnodesdim(v, (i, j, k...))
Base.setindex!(v::S, _, i, j, k...) = errnodesdim(v, (i, j, k...))
errnodesdim(v, i) = err(
    v,
    "Cannot index into nodes with $(length(i)) dimensions: [$(join_elided(i, ", "))].",
)
check_label(v::S, l::Symbol) = N.check_label(l, index(v), classname(v))
check_ref(v::S, i::Int) = check_index(v, i)
check_ref(v::S, l::Symbol) = check_label(v, l)
check_ref(v::S, x::Any) = err(
    v,
    "Views are indexed with indices (::Int) or labels (::Symbol).
     Cannot index with: $(repr(x)) ::$(typeof(x)).",
)

function check_index(v::S, i::Int)
    n, s = ns(length(v))
    class = repr(classname(v))
    i in 1:n || err(v, "Cannot index with [$i] into a view with $n $class node$s.")
    i
end

# Assuming checked input.
N.to_label(v::S, i::Int) = N.to_label(index(v), i)
N.to_index(v::S, l::Symbol) = N.to_index(index(v), l)
