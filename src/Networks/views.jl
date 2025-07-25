"""
A view into network graph, node or edge data,
responsible for enforcing the COW pattern.
"""
abstract type View{T} end
Base.eltype(::View{T}) where {T} = T

"""
Graph-level view.
"""
struct GraphView{T} <: View{T}
    network::Network # Prevent from garbage-collection as long as the view is live.
    entry::Entry{T}
end
network(v::GraphView) = getfield(v, :network)
entry(v::GraphView) = getfield(v, :entry)

"""
Node-level view.
"""
struct NodesView{T,R<:Restriction} <: View{T}
    class::Class{R} # Prevent from garbage collection as long as the view is live.
    entry::Entry{Vector{T}}
end
class(v::NodesView) = getfield(v, :class)
entry(v::NodesView) = getfield(v, :entry)
restrict_type(::NodesView{T,R}) where {T,R} = R

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
# Ergonomics.

# Forward basic operators to views.
Base.getindex(v::View, x, i...) = read(v, getindex, x, i...)
Base.setindex!(v::View, x, i...) = mutate!(v, setindex!, x, i...)

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
Base.length(v::View) = read(v, length)
Base.size(v::View) = read(v, size)
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
