"""
Responsible for reference-counting one piece of data value
against the networks owning it.
"""
mutable struct Field{T}
    value::T
    n_networks::UInt64
    Field(v) = new{typeof(v)}(v, 1) # Always created for exactly 1 network.
end
value(f::Field) = getfield(f, :value)
n_networks(f::Field) = getfield(f, :n_networks)
Base.eltype(f::Field) = typeof(value(f))
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
field(e::Entry) = getfield(e, :field)
Base.eltype(e::Entry) = eltype(field(e))
n_networks(e::Entry) = n_networks(field(e))

# Protect from misuse.
Base.getproperty(::Field, ::Symbol) = throw("Don't access fields directly.")
Base.getproperty(::Entry, ::Symbol) = throw("Don't access entries directly.")
Base.setproperty!(::Field, ::Symbol, _) = throw("Don't access fields directly.")
Base.setproperty!(::Entry, ::Symbol, _) = throw("Don't access entries directly.")
Base.deepcopy(::Field) = throw("Deepcopying the field would break its logic.")
Base.deepcopy(::Entry) = throw("Deepcopying the entry would break its logic.")

# ==========================================================================================
# Basic transactional API for COW + concurrence control.

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
Extract a reference to underlying entry data for read-only access during transaction.
"""
ref_for_reading(e::Entry) = value(field(e))

"""
Extract a reference to underlying entry data for mutable access during transaction.
Triggers COW if needed.
"""
function ref_for_mutating(e::Entry)
    field = Networks.field(e)
    v = value(field)
    if n_networks(field) == 1
        v # The field is not shared: just extract.
    else
        # The field is shared: Clone-On-Write!
        clone = deepcopy(v)
        decref(field) # Detach from original.
        setfield!(e, :field, Field(clone))
        clone
    end
end

"""
Basic transactional reassignment through an entry, triggering COW if needed.
(See module-level doc.)
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
    err("Cannot assign to field of type $T:\n$(repr(new)) ::$(O)")
export reassign!

"""
Complex transactional operation,
mixing read-only, mutation and reassignmnent through the entries passed as tuples.
(See module-level doc.)

The closure passed receives two corresponding tuples of references `(writes, reads)`
as arguments to work on.
The data accessible through `reads` must not be mutated.
The references obtained or any projection into them must not escape the closure.
The closure must return `(res, news)`
with `res` an arbitrary return value for the caller,
and `news` the tuple of new values to reassign the entries passed as `assign` to.

Alternate transactional methods like `read`, `mutate!`, `modify!` or `readassign!`.
are just ergonomic wrappers around `mix!`.
"""
Entries = Tuple{Vararg{Entry}}
function mix!(f!, write::Entries, read::Entries, assign::Entries)
    # Extract values from the fields,
    # accounting for COW + possible concurrent accesses in the future.
    read = map(ref_for_reading, read)
    write = map(ref_for_mutating, write)

    # Execute user code,
    # trusting that no mutation via `read`
    # and no references leaks occurs in there.
    res, new = f!(write, read)

    # Reassign entries to the values produced.
    na, nw = length.((assign, new))
    length(assign) == length(new) || throw("Received $na entries to reassign, \
                                            but the closure produced $nw values.")
    map(reassign!, zip(assign, new))

    # Return the desired result.
    res
end
export mix!
