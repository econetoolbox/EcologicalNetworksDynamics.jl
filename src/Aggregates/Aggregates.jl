# At the heart of the package *data* is a flat aggregate of various 'fields',
# added and modified by the various high-level 'components', but never removed.
# As they are often supposed to be shared and only partly mutated,
# protect the fields with a Copy-On-Write (COW) pattern,
# and best-attempt to make it thread-safe.

module Aggregates

# ==========================================================================================
# Base structure.

# Count the number of different models
# currently relying on a field's value.
mutable struct Field{T}
    value::T
    @atomic n_aggregates::UInt64
    Field{T}(v) where {T} = new(v, 1) # Always created for exactly 1 aggregate.
end
Base.eltype(::Field{T}) where {T} = T

# Indirect connect to field
# so as to easily update it when COW happens.
# Protect with a mutex.
mutable struct Entry{T}
    field::Field{T}
    mutex::ReentrantLock
    Entry{T}(field::Field{T}) where {T} = new(field, ReentrantLock())
end
Base.eltype(::Entry{T}) where {T} = T

# Aggregate fields together with a flat symbol-access.
# Type-unstable.
mutable struct Aggregate
    entries::Dict{Symbol,Entry}
    mutex::ReentrantLock
    Aggregate() = finalizer(drop!, new(Dict(), ReentrantLock()))
    Aggregate(entries) = finalizer(drop!, new(entries, ReentrantLock()))
end
export Aggregate

# A protected view into one field of one aggregate.
# Responsible for mutex accesses, and COW enforcement on mutation.
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
    m = mutex(a)
    entries = fields(a)
    # Create entry upfront, assuming key errors are a bug.
    entry = Entry{T}(Field{T}(value))
    lock(m)
    try
        haskey(entries, name) && throw("Aggregate already contains field :$name.")
        entries[name] = entry
    finally
        unlock(m)
    end
    nothing
end
export add_field!

# Fork the model, reusing all its field values,
# by incrementing their counts instead of copying.
function Base.copy(a::Aggregate)
    m = mutex(a)
    entries = fields(a)
    lock(m)
    Aggregate(try
        new_entries = Dict{Symbol,Entry}()
        for (name, entry) in entries
            lock(entry.mutex)
            new = try
                f = entry.field
                @atomic f.n_aggregates += 1
                Entry{eltype(f)}(f)
            finally
                unlock(entry.mutex)
            end
            new_entries[name] = new
        end
        new_entries
    finally
        unlock(m)
    end)
end

# Drop the model, reducing field counts.
function drop!(a::Aggregate)
    # If we are being garbage-collected,
    # then we have exclusive access: don't need to lock.
    for entry in values(fields(a))
        @atomic entry.field.n_aggregates -= 1
    end
end

# Get a view into one model field.
function view(a::Aggregate, name::Symbol)
    m = mutex(a)
    entries = fields(a)
    entry = begin
        lock(m)
        try
            entries[name]
        catch err
            err isa KeyError && rethrow("Aggregate has no field :$name.")
            rethrow(err)
        finally
            unlock(m)
        end
    end
    View{eltype(entry)}(entry, a)
end
export view

# Read through a view, providing closure called with secure access to underlying value.
# /!\ Do not mutate or leak reference to the value received.
function scan(f, v::View)
    e = entry(v)
    lock(e.mutex)
    try
        f(e.field.value)
    finally
        unlock(e.mutex)
    end
end
export scan

# Write through a view, providid closure called with secure access to underlying value.
# /!\ Do not leak reference to the value received.
function mutate!(f!, v::View{T}) where {T}
    e = entry(v)
    lock(e.mutex)
    try
        if (@atomic e.field.n_aggregates) == 1
            # The field is not shared: just mutate.
            f!(e.field.value)
        else
            # The field is shared: clone on write!
            clone = deepcopy(e.field.value)
            @atomic e.field.n_aggregates -= 1 # Detach from original.
            res = f!(clone)
            e.field = Field{T}(clone)
            res
        end
    finally
        unlock(e.mutex)
    end
end
export mutate!

# Reassign whole field through a view.
function reassign!(v::View{T}, new::T) where {T}
    e = entry(v)
    lock(e.mutex)
    try
        if (@atomic e.field.n_aggregates) == 1
            e.field.value = new
        else
            @atomic e.field.n_aggregates -= 1
            e.field = Field{T}(new)
        end
    finally
        unlock(e.mutex)
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

end
