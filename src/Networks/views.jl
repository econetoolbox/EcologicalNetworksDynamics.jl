"""
A view into network graph, node or edge data,
responsible for enforcing the COW pattern.
"""
abstract type View{T} end
eltype(::View{T}) where {T} = T

"""
Node-level view.
"""
struct NodesView{T,R<:Restriction} <: View{T}
    class::Class{R}
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

"""
Read through a view,
providing closure called with secure access to underlying value.
⚠ Do not mutate or leak references into the value received.
This might seem cumbersome,
but it is expected to make it possible to make the network thread-safe in the future.
"""
function Base.read(f, v::View)
    e = entry(v)
    f(e.field.value)
end
Base.read(v::View, f, args...; kwargs...) = read(v -> f(v, args...; kwargs...), v)

"""
Write through a view,
providing closure called with secure access to underlying value.
⚠ Do not leak references into the value received.
This might seem cumbersome,
but it is expected to make it possible to make the network thread-safe in the future.
"""
function mutate!(f!, v::View)
    e = entry(v)
    if e.field.n_aggregates == 1
        # The field is not shared: just mutate.
        f!(e.field.value)
    else
        # The field is shared: Clone-On-Write!
        clone = deepcopy(e.field.value)
        res = f!(clone)
        e.field.n_aggregates -= 1 # Detach from original.
        T = eltype(v)
        e.field = Field{T}(clone)
        res
    end
end
mutate!(v::View, f!, args...; kwargs...) = mutate!(v -> f!(v, args...; kwargs...), v)
export mutate!

"""
Reassign the whole field through a view.
"""
function reassign!(v::View{T}, new::T) where {T}
    e = entry(v)
    if e.field.n_aggregates == 1
        e.field.value = new
    else
        e.field.n_aggregates -= 1
        e.field = Field{T}(new)
    end
    v
end
reassign!(::View{T}, new::O) where {T,O} =
    argerr("Cannot assign to field of type $T:\n$new ::$(O)")
export reassign!

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
    e = entry(v)
    (; n_networks, value) = e.field
    n = nnet(n_networks)
    V = typeof(v)
    print(io, "$V$n($value)")
end

# Elide number of aggregates if non-shared.
nnet(n) = n == 1 ? "" : "<$n>" # (display if zero though 'cause it's a bug)
