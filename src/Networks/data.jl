"""
Responsible for reference-counting one piece of data value
against the networks owning it.
"""
mutable struct Field{T}
    value::T
    n_networks::UInt64
    Field{T}(v) where {T} = new(v, 1) # Always created for exactly 1 network.
end

"""
Responsible for protecting fields with a boxing-indirection
against both the network and its views.
"""
mutable struct Entry{T}
    field::Field{T}
    Entry{T}(field::Field{T}) where {T} = new(field)
end
Base.eltype(::Field{T}) where {T} = T
Base.eltype(::Entry{T}) where {T} = T

