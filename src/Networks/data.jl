"""
Responsible for reference-counting one piece of data value
against the networks owning it.
"""
mutable struct Field{T}
    value::T
    n_networks::UInt64
    Field(v) = new{typeof(v)}(v, 1) # Always created for exactly 1 network.
end
Base.eltype(f::Field) = typeof(value(f))
value(f::Field) = getfield(f, :value)
n_networks(f::Field) = getfield(f, :n_networks)
incref(f::Field) = setfield!(f, :n_networks, n_networks(f) + 1)
decref(f::Field) = setfield!(f, :n_networks, n_networks(f) - 1)

"""
Responsible for protecting fields with a boxing-indirection
against both the network and its views.
"""
mutable struct Entry{T}
    field::Field{T}
    Entry(f::Field) = new{eltype(f)}(f)
    Entry(v) = new{typeof(v)}(Field(v))
end
Base.eltype(e::Entry) = eltype(field(e))
field(e::Entry) = getfield(e, :field)
n_networks(e::Entry) = n_networks(field(e))

# Protect from misuse.
Base.getproperty(::Field, ::Symbol) = throw("Don't access fields directly.")
Base.getproperty(::Entry, ::Symbol) = throw("Don't access entries directly.")
Base.setproperty!(::Field, ::Symbol, _) = throw("Don't access fields directly.")
Base.setproperty!(::Entry, ::Symbol, _) = throw("Don't access entries directly.")
Base.deepcopy(::Field) = throw("Deepcopying the field would break its logic.")
Base.deepcopy(::Entry) = throw("Deepcopying the entry would break its logic.")

#-------------------------------------------------------------------------------------------

"""
Increment underlying field count when copying,
call when COW-pying the whole network.
"""
function fork(e::Entry)
    f = field(e)
    incref(f)
    Entry(f)
end
fork(d::Dict) = Dict(k => fork(e) for (k, e) in d) # (typical)

"""
Read through an entry,
providing closure called with secure access to underlying value.
⚠ Do not mutate or leak references into the value received.
This might seem cumbersome,
but it is expected to make it possible to make the network thread-safe in the future.
"""
Base.read(f, e::Entry) = f(value(field(e)))
Base.read(e::Entry, f, args...; kwargs...) = read(e -> f(e, args...; kwargs...), e)

"""
Write through an entry,
providing closure called with secure access to underlying value.
⚠ Do not leak references into the value received.
This might seem cumbersome,
but it is expected to make it possible to make the network thread-safe in the future.
"""
function mutate!(f!, e::Entry)
    field = Networks.field(e)
    v = value(field)
    if n_networks(field) == 1
        # The field is not shared: just mutate.
        f!(v)
    else
        # The field is shared: Clone-On-Write!
        clone = deepcopy(v)
        res = f!(clone)
        decref(field) # Detach from original.
        T = eltype(e)
        setfield!(e, :field, Field(clone))
        res
    end
end
mutate!(e::Entry, f!, args...; kwargs...) = mutate!(e -> f!(e, args...; kwargs...), e)
export mutate!

"""
Reassign the whole field through an entry.
"""
function reassign!(e::Entry{T}, new::T) where {T}
    field = Networks.field(e)
    if n_networks(field) == 1
        setfield!(field, :value, new)
    else
        decref(field)
        setfield!(e, :field, Field(new))
    end
    e
end
reassign!(::Entry{T}, new::O) where {T,O} =
    argerr("Cannot assign to field of type $T:\n$new ::$(O)")
export reassign!
