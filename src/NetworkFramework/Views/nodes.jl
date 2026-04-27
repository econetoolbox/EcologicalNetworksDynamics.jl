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
struct NodesDataView{d,T} <: AbstractVector{T}
    model::Model
    view::N.NodesView{T}
end
export NodesDataView
function data_view(m::Model, d::D.NodeField)
    (class, fieldname) = D.content(d)
    n = NF.network(m)
    view = N.nodes_view(n, class, fieldname)
    T = eltype(view)
    NodesDataView{d,T}(m, view)
end
export data_view
S = NodesDataView
N.restriction(s::S) = N.class(s).restriction
Base.size(s::S) = (s |> N.view |> length,)
Base.getindex(s::S, ref) = getindex(N.view(s), check_ref(s, ref))
function Base.setindex!(s::S, x, ref)
    ref = check_ref(s, ref)
    x = check_write(s, x, ref)
    setindex!(N.view(s), x, ref)
end
extract(s::S) = read(collect, N.entry(s))

#-------------------------------------------------------------------------------------------
"""
View into nodes class data
from the perspective of a superclass,
resulting in incomplete / sparse data.
Parametrized by SparseNodesData dispatcher.
"""
struct SparseNodesDataView{d,T} <: AbstractSparseVector{T,Int}
    model::Model
    view::N.NodesView{T}
end
export SparseNodesDataView
function data_view(m::Model, d::D.SparseNodeField)
    (class, fieldname, _) = D.content(d)
    n = NF.network(m)
    view = N.nodes_view(n, class, fieldname)
    T = eltype(view)
    SparseNodesDataView{d,T}(m, view)
end
S = SparseNodesDataView
D.parent(s::S) = D.parent(dispatcher(s))
N.restriction(s::S) = N.restriction(N.network(s), D.class(s), D.parent(s))
Base.size(s::S) = (N.n_nodes(N.network(s), D.parent(s)),)
Base.getindex(s::S, l::Symbol) = getindex(N.view(s), check_ref(s, l))
function Base.setindex!(s::S, x, l::Symbol)
    l = check_ref(s, l)
    x = check_write(s, x, l)
    setindex!(N.view(s), x, l)
end

function Base.getindex(s::S, i::Int)
    i = check_ref(s, i)
    i = restrict_index(s, i)
    read(N.entry(s), getindex, i)
end

function Base.setindex!(s::S, x, i::Int)
    i = check_ref(s, i)
    i = restrict_index(s, i)
    x = check_write(s, x, i)
    mutate!(N.entry(s), setindex!, x, i)
end

function restrict_index(s::S, i::Int)
    r = N.restriction(s)
    if !(i in r)
        class = repr(D.class(s))
        parent = repr(D.parent(s))
        err(s, "Node $i in $parent is not a node in $class.")
    end
    N.tolocal(i, r)
end

# Duty to AbstractSparseVector..?
SparseArrays.nonzeroinds(s::S) = s |> N.restriction |> N.indices |> collect
SparseArrays.nonzeros(s::S) = read(collect, N.entry(s))
SparseArrays.findnz(s::S) = (SparseArrays.nonzeroinds(s), nonzeros(s))
SparseArrays.nnz(s::S) = s |> N.restriction |> length

function extract(s::S)
    T = eltype(s)
    n = length(s)
    r = N.restriction(s)
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

AbstractNodesDataView{d,T} = Union{NodesDataView{d,T},SparseNodesDataView{d,T}}
S = AbstractNodesDataView
N.class(s::S) = s |> N.view |> N.class
Base.setindex!(s::S, _) = errnodesdim(s, ())
Base.setindex!(s::S, _, i, j, k...) = errnodesdim(s, (i, j, k...))

"""
Generic checking logic, assuming checked ref,
delegating to the `mutate_check` function later defined with typical node data components.
"""
check_write(s::S, x, ref) =
    if D.readonly(s)
        err(s, "Values of $(repr(D.field(s))) are readonly.")
    else
        x = try
            d = dispatcher(s)
            m = NF.model(s)
            NF.mutate_check(d, m, x, ref)
        catch e
            e isa InputError || rethrow(e)
            rethrow(V.WriteError(e.mess, D.field(s), ref, x))
        end
        x
    end

# Mirror Julia's error in this case.
check_write(s::S, _, ::UnitRange) = err(
    s,
    "Indexed assignment with a single value to possibly many locations \
     is not supported; perhaps use broadcasting `.=` instead?",
)

# ==========================================================================================
# Immutable topology views.

"""
An immutable view into network class label names.
Parametrized by NodeClass dispatcher.
"""
struct NodesNamesView{d} <: AbstractVector{Symbol}
    # Overkill right now, but keep it for future compat.
    model::Model
    index::N.Index # Cache an underlying class index alias.
end
export NodesNamesView
function names_view(m::Model, d::D.NodeClass)
    n = NF.network(m)
    class = D.class(d)
    index = N.class(n, class).index
    NodesNamesView{d}(m, index)
end
S = NodesNamesView
N.index(s::S) = getfield(s, :index)
Base.size(s::S) = (s |> N.index |> length,)
Base.getindex(s::S, i::Int) = N.to_label(s, check_ref(s, i))
Base.getindex(s::S, l::Symbol) = check_ref(s, l) # (not exactly useful but consistent)
Base.setindex!(s::S, _...) =
    err(s, "Cannot change :$(D.class(s)) nodes names after they have been set.")
export names_view
extract(s::S) = copy(N.index(s).reverse)

#-------------------------------------------------------------------------------------------
"""
An immutable view into network class restriction mask.
Parametrized by NodeMask dispatcher.
"""
struct NodesMaskView{d} <: AbstractVector{Bool}
    model::Model
    restriction::N.Restriction
end
export NodesMaskView
function mask_view(m::Model, d::D.NodeMask)
    (class, parent) = D.content(d)
    n = NF.network(m)
    r = N.restriction(n, class, parent)
    NodesMaskView{d}(m, r)
end
export mask_view
S = NodesMaskView
D.parent(s::S) = D.parent(dispatcher(s))
N.parent(s::S) = N.class(N.network(s), D.parent(s))
N.restriction(s::S) = getfield(s, :restriction)
function Base.size(s::S)
    net = N.network(s)
    p = D.parent(s)
    n = isnothing(p) ? N.n_nodes(net) : length(N.class(net, p))
    (n,)
end
Base.getindex(s::S, i::Int) = check_ref(s, i) in N.restriction(s)
Base.getindex(s::S, l::Symbol) = N.is_label(
    isnothing(D.parent(s)) ? check_ref(s, l) : N.check_label(s, N.class(s)),
    N.class(s),
)
Base.setindex!(s::S, _...) =
    err(s, "Cannot change :$(D.class(s)) nodes mask after it has been set.")
function extract(s::S)
    res = spzeros(Bool, length(s))
    for i in s |> restriction |> N.indices
        res[i] = true
    end
    res
end

#-------------------------------------------------------------------------------------------
# Common to topology node views.

NodeTopologyView{d} = Union{NodesNamesView{d},NodesMaskView{d}}
S = NodeTopologyView
N.class(s::S) = N.class(N.network(s), D.class(s))
Base.getindex(s::S, ref) = @invoke getindex(s::AbstractVector, check_ref(s, ref))

# ==========================================================================================
# Common to all node views.

NodesView{d} = Union{AbstractNodesDataView{d},NodesNamesView{d},NodesMaskView{d}}
S = NodesView
N.index(s::S) = N.class(s).index
D.class(s::S) = D.class(dispatcher(s))
Base.getindex(s::S) = errnodesdim(s, ())
Base.getindex(s::S, i, j, k...) = errnodesdim(s, (i, j, k...))
errnodesdim(s, i) = err(
    s,
    "Cannot index into nodes with $(length(i)) dimensions: [$(EN.join_elided(i, ", "))].",
)

# Entrypoint for all direct indices.
check_ref(s::S, i::Int) = check_index(s, i)
check_ref(s::S, l::Symbol) = check_label(s, l)

function check_index(s::S, i::Int)
    class = repr(D.class(s))
    n, s_ = ns(length(s))
    i in 1:n || err(s, "Cannot index with [$i] into a class with $n $class node$s_.")
    i
end

check_label(s::S, l::Symbol) =
    try
        N.check_label(l, N.index(s), D.class(s))
    catch e
        e isa N.LabelError || rethrow(e)
        err(s, sprint(showerror, e), rethrow)
    end

# Assuming checked input.
N.to_label(s::S, i) = N.to_label(N.index(s), i)
N.to_index(s::S, l) = N.to_index(N.index(s), l)
