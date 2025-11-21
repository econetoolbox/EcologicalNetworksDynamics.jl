"""
A view into graph-level data.
"""
struct GraphView{T}
    network::Network # Protect from garbage-collection as long as the view is live.
    entry::Entry{T}
end

"""
A view into node-level data.
"""
struct NodesView{T} <: AbstractVector{T}
    # Protect from garbage collection as long as the view is live.
    # Useful to retrieve parents/grandparent classes when exporting nodes.
    network::Network
    # Direct acces without indexing network classes.
    class::Class
    entry::Entry{Vector{T}}
end
class(v::NodesView) = getfield(v, :class)

struct EdgesView{T} <: AbstractVector{T}
    network::Network
    web::Web
    entry::Entry{Vector{T}}
end
web(v::EdgesView) = getfield(v, :web)

# Abstract over levels.
# (cannot use abstract type View{T} because of AbstractVector{T} subtyping already)
const View{T} = Union{GraphView{T},NodesView{T},EdgesView{T}}
entry(v::View) = getfield(v, :entry)
network(v::View) = getfield(v, :network)
Base.eltype(::View{T}) where {T} = T
export entry, network

#-------------------------------------------------------------------------------------------

# Protect from misuse.
Base.getproperty(::View, ::Symbol) = throw("View fields are private.")
Base.setproperty!(::View, ::Symbol, _) = throw("View fields are private.")
Base.deepcopy(::View) = throw("Deepcopying the view would break its logic.")
Base.copy(v::View) = v # There is no use in a copy.

# Forward to underlying entry.
n_networks(v::View) = n_networks(entry(v))

#-------------------------------------------------------------------------------------------
# Indexing with integers or labels.

const ArrayView{T} = Union{GraphView{<:AbstractVector{T}},NodesView{T},EdgesView{T}}
Base.size(v::ArrayView) = read(v, size)
Base.getindex(v::ArrayView, i) = read(v, getindex, i)
Base.setindex!(v::ArrayView, x, i) = mutate!(v, setindex!, x, i)

function Base.getindex(v::NodesView, label::Symbol)
    c, e = class(v), entry(v)
    check_label(label, c.index, c.name)
    i = c.index[label]
    read(e) do array
        array[i]
    end
end

function Base.setindex!(v::NodesView, new, label::Symbol)
    c, e = class(v), entry(v)
    check_label(label, c.index, c.name)
    i = c.index[label]
    mutate!(e) do array
        array[i] = new
    end
end

#-------------------------------------------------------------------------------------------
# Index edge views with two dimensions with tuples.
# Don't splat the tuples for julia not to mistake these views for matrices.

function to_linear(v::EdgesView, i::Int, j::Int)
    web = Networks.web(v)
    top = web.topology
    for (i, count, what) in ((i, n_sources, "source"), (j, n_targets, "target"))
        n, s = ns(count(top))
        1 <= i <= n || err("Not an index for web $(repr(web.name)) with $n $what$s: $i.")
    end
    is_edge(top, i, j) || err("Not an edge in web $(repr(web.name)): $((i, j)).")
    edge(top, i, j)
end
Base.getindex(v::EdgesView, (i, j)::Tuple{Int,Int}) = getindex(v, to_linear(v, i, j))
Base.setindex!(v::EdgesView, x, (i, j)::Tuple{Int,Int}) =
    setindex!(v, x, to_linear(v, i, j))

function Base.getindex(v::EdgesView, (s, t)::Tuple{Symbol,Symbol})
    w, e = web(v), entry(v)
    c = network(v).classes
    src, tgt = c[w.source], c[w.target]
    read(e) do array
        i = src.index[s]
        j = tgt.index[t]
        array[to_linear(v, i, j)]
    end
end

function Base.setindex!(v::EdgesView, new, (s, t)::Tuple{Symbol,Symbol})
    w, e = web(v), entry(v)
    c = network(v).classes
    src, tgt = c[w.source], c[w.target]
    mutate!(e) do array
        i = src.index[s]
        j = tgt.index[t]
        array[to_linear(v, i, j)] = new
    end
end

#-------------------------------------------------------------------------------------------
# Ergonomics.

# Forward basic operators to views.
# TODO: now easy to accept more operands with like read((...) -> $op(...), ...) ?
macro binop(op)
    quote
        Base.$op(lhs::View, rhs) = read(v -> $op(v, rhs), lhs)
        Base.$op(lhs, rhs::View) = read(v -> $op(lhs, v), rhs)
        Base.$op(lhs::View, rhs::View) = read(v -> $op(v, rhs), lhs)
    end
end
@binop +
@binop -
@binop *
@binop /
@binop %
@binop ==
@binop >=
@binop <=
@binop >
@binop <
@binop ≈
Base.:!(v::View) = read(v -> !v, v)

#-------------------------------------------------------------------------------------------
# Display.

function Base.show(io::IO, v::View)
    V = typeof(v)
    n = nnet(n_networks(v))
    read(v) do value
        print(io, "$(nameof(V))$n($value)")
    end
end
