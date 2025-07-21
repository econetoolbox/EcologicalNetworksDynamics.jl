# At the heart of the package *data* is a flat aggregate of various 'fields',
# added and modified by the various high-level 'components', but never removed.
# As they are often supposed to be shared and only partly mutated,
# protect the fields with a Copy-On-Write (COW) pattern.
# /!\ Protecting this against concurrency would require Read-Write Locks
# but there is no such thing in Julia yet.
# This makes the whole data structure unsuitable for shared memory.

module Aggregates

# ==========================================================================================
# Base structure.

# Count the number of different models
# currently relying on a field's value.
mutable struct Field{T}
    value::T
    n_aggregates::UInt64
    Field{T}(v) where {T} = new(v, 1) # Always created for exactly 1 aggregate.
end
Base.eltype(::Field{T}) where {T} = T

# Indirection between an aggregate and its field
# so as to easily update it when COW happens.
mutable struct Entry{T}
    field::Field{T}
    Entry{T}(field::Field{T}) where {T} = new(field)
end
Base.eltype(::Entry{T}) where {T} = T

# Aggregate fields together with a flat symbol-access.
# Type-unstable.
mutable struct Aggregate
    entries::Dict{Symbol,Entry}
    Aggregate() = finalizer(drop!, new(Dict()))
    Aggregate(entries) = finalizer(drop!, new(entries))
end
export Aggregate

# A protected view into one field of one aggregate.
# Responsible COW enforcement on mutation.
struct View{T}
    entry::Entry{T}
    aggregate::Aggregate # For aggregates to avoid GC when only views of them remain.
end

# ==========================================================================================
# Protect internals.
fields(a::Aggregate) = getfield(a, :entries) # (to avoid `entries = entries(a)`)
mutex(a::Aggregate) = getfield(a, :mutex)
Base.deepcopy(::Aggregate) = throw("Deepcopying the aggregate would break its logic.")

Base.getproperty(::View, ::Symbol) = throw("View fields are private.")
Base.setproperty!(::View, ::Symbol, _) = throw("View fields are private.")
entry(v::View) = getfield(v, :entry)
aggregate(v::View) = getfield(v, :aggregate)
Base.deepcopy(::View) = throw("Deepcopying the view would break its logic.")
Base.copy(v::View) = v # There is no use in a copy.

# ==========================================================================================
# Primitives.

# Insert new value into the aggregate.
function add_field!(a::Aggregate, name::Symbol, value::T) where {T}
    hasmethod(deepcopy, (T,)) || throw("Can't add non-deepcopy field.")
    entries = fields(a)
    haskey(entries, name) && throw("Aggregate already contains field :$name.")
    entries[name] = Entry{T}(Field{T}(value))
    nothing
end
export add_field!

# Fork the model, reusing all its field values,
# by incrementing their counts instead of copying.
function Base.copy(a::Aggregate)
    entries = fields(a)
    new_entries = Dict{Symbol,Entry}()
    for (name, entry) in entries
        f = entry.field
        f.n_aggregates += 1
        new = Entry{eltype(f)}(f)
        new_entries[name] = new
    end
    Aggregate(new_entries)
end

# Drop the model, reducing field counts.
drop!(a::Aggregate) =
    for entry in values(fields(a))
        entry.field.n_aggregates -= 1
    end

# Get a view into one model field.
function view(a::Aggregate, name::Symbol)
    entries = fields(a)
    entry = try
        entries[name]
    catch err
        err isa KeyError && rethrow("Aggregate has no field :$name.")
        rethrow(err)
    end
    View{eltype(entry)}(entry, a)
end
export view

# Read through a view, providing closure called with secure access to underlying value.
# /!\ Do not mutate or leak reference to the value received.
function scan(f, v::View)
    e = entry(v)
    f(e.field.value)
end
export scan

# Write through a view, providid closure called with secure access to underlying value.
# /!\ Do not leak reference to the value received.
function mutate!(f!, v::View{T}) where {T}
    e = entry(v)
    if e.field.n_aggregates == 1
        # The field is not shared: just mutate.
        f!(e.field.value)
    else
        # The field is shared: clone on write!
        clone = deepcopy(e.field.value)
        e.field.n_aggregates -= 1 # Detach from original.
        res = f!(clone)
        e.field = Field{T}(clone)
        res
    end
end
export mutate!

# Reassign whole field through a view.
function reassign!(v::View{T}, new::T) where {T}
    e = entry(v)
    if e.field.n_aggregates == 1
        e.field.value = new
    else
        e.field.n_aggregates -= 1
        e.field = Field{T}(new)
    end
    nothing
end
export reassign!

# ==========================================================================================
# Ergonomics.

# Access fields as properties, actually get views into them.
Base.getproperty(a::Aggregate, p::Symbol) = view(a, p)
Base.setproperty!(a::Aggregate, p::Symbol, v) = reassign!(view(a, p), v)

# Assuming the value is the first argument,
# ease ergonomics of reading/writing to them.
scan(v::View, f, args...; kwargs...) =
    scan(v) do v
        f(v, args...; kwargs...)
    end
mutate!(v::View, f!, args...; kwargs...) =
    mutate!(v) do v
        f!(v, args...; kwargs...)
    end

# Forward basic operators to views.
Base.getindex(v::View, x, i...) = scan(v -> getindex(v, x, i...), v)
Base.setindex!(v::View, x, i...) = mutate!(v -> setindex!(v, x, i...), v)

macro binop(op)
    quote
        Base.$op(lhs::View, rhs) = scan(v -> $op(v, rhs), lhs)
        Base.$op(lhs, rhs::View) = scan(v -> $op(lhs, v), rhs)
        Base.$op(lhs::View, rhs::View) = scan(v -> $op(v, rhs), lhs)
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
Base.:!(v::View) = scan(v -> !v, v)
Base.length(v::View) = scan(v, length)
Base.size(v::View) = scan(v, size)
Base.iterate(v::View, args...) = scan(v, iterate, args...)

#-------------------------------------------------------------------------------------------
# Errors.
reassign!(::View{T}, new::O) where {T,O} =
    throw(ArgumentError("Cannot assign to field of type $T:\n$new ::$(O)"))

#-------------------------------------------------------------------------------------------
#Display.

function Base.show(io::IO, a::Aggregate)
    print(io, "Aggregate({")
    entries = fields(a)
    first = true
    for (name, e) in entries
        (; n_aggregates, value) = e.field
        n = nagg(n_aggregates)
        if !first
            print(io, ", ")
        end
        print(io, "$name$n: $(value)")
        first = false
    end
    print(io, "})")
end

function Base.show(io::IO, ::MIME"text/plain", a::Aggregate)
    print(io, "Aggregate")
    entries = fields(a)
    if isempty(entries)
        print(io, " with no fields.")
    else
        print(io, ":")
        for (name, e) in entries
            (; n_aggregates, value) = e.field
            println(io)
            n = nagg(n_aggregates)
            print(io, "  $name$n: $(value)")
        end
    end
end

function Base.show(io::IO, v::View)
    e = entry(v)
    (; n_aggregates, value) = e.field
    n = nagg(n_aggregates)
    print(io, "View$n($value)")
end

# Elide number of aggregates if non-shared.
nagg(n) = n == 1 ? "" : "<$n>" # (display if zero though 'cause it's a bug)

end
