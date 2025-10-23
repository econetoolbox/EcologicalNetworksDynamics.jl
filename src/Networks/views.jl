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

struct EdgesView{T} <: AbstractVector{T} end

# Abstract over levels.
# (cannot use abstract type View{T} because of AbstractVector{T} subtyping already)
const View{T} = Union{GraphView{T},NodesView{T},EdgesView{T}}
entry(v::View) = getfield(v, :entry)
network(v::View) = getfield(v, :network)
Base.eltype(::View{T}) where {T} = T

#-------------------------------------------------------------------------------------------

# Protect from misuse.
Base.getproperty(::View, ::Symbol) = throw("View fields are private.")
Base.setproperty!(::View, ::Symbol, _) = throw("View fields are private.")
Base.deepcopy(::View) = throw("Deepcopying the view would break its logic.")
Base.copy(v::View) = v # There is no use in a copy.

# Forward to underlying entry.
Base.read(v::View, args...; kwargs...) = read(entry(v), args...; kwargs...)
mutate!(v::View, args...; kwargs...) = mutate!(entry(v), args...; kwargs...)
reassign!(v::View, args...; kwargs...) = reassign!(entry(v), args...; kwargs...)
Base.read(f, v::View) = read(f, entry(v))
mutate!(f!, v::View) = mutate!(f!, entry(v))
n_networks(v::View) = n_networks(entry(v))

#-------------------------------------------------------------------------------------------
# Indexing with integers or labels.

const ArrayView{T} = Union{GraphView{<:AbstractVector{T}},NodesView{T},EdgesView{T}}
Base.size(v::ArrayView) = read(v, size)
Base.getindex(v::ArrayView, i) = read(v, getindex, i)
Base.setindex!(v::ArrayView, x, i) = mutate!(v, setindex!, x, i)

function Base.getindex(v::NodesView, label::Symbol)
    c, e = class(v), entry(v)
    i = read(c.index, getindex, label)
    read(e, getindex, i)
end

function Base.setindex!(v::NodesView, new, label::Symbol)
    c, e = class(v), entry(v)
    i = read(c.index, getindex, label)
    mutate!(e, setindex!, new, i)
end

#-------------------------------------------------------------------------------------------
# Ergonomics.

# Forward basic operators to views.
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
Base.iterate(v::View, args...) = read(v, iterate, args...)

#-------------------------------------------------------------------------------------------
# Display.

function Base.show(io::IO, v::View)
    V = typeof(v)
    n = nnet(n_networks(v))
    read(v) do value
        print(io, "$(nameof(V))$n($value)")
    end
end
