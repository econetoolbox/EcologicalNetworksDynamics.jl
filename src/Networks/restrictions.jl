"""
Specify how nodes are filtered or "restricted"
from one class to its subclass.
"""
abstract type Restriction end

# ==========================================================================================
# The various kinds of restrictions.

"""
Root class 'no-restriction', including all nodes.
"""
mutable struct Full <: Restriction
    n::Int # Total number of nodes in the network.
end

"""
Restrict with a range of nodes.
"""
struct Range <: Restriction
    range::UnitRange{Int} # Indices selected from the parent class.
end

"""
Restrict with a sparse allow-list of nodes.
"""
struct Sparse <: Restriction
    # Indices included from the parent class.
    # Keep sorted for efficient query.
    select::Vector{Int}
end

"""
Construct from a boolean mask.
"""
sparse_from_mask(mask) = Sparse([i for (i, included) in enumerate(mask) if included])

#-------------------------------------------------------------------------------------------
# Query restrictions.

"""
Number of nodes in the restriction.
"""
Base.length(::Restriction) = throw("unimplemented")
Base.length(f::Full) = f.n
Base.length(r::Range) = length(r.range)
Base.length(s::Sparse) = length(s.select)

"""
Given an index *from the parent class*,
query whether it also belongs to the restricted subclass.
"""
Base.in(::Int, ::Restriction) = throw("unimplemented")
Base.in(::Int, ::Full) = true
Base.in(i::Int, r::Range) = i in r.range
Base.in(i::Int, s::Sparse) = insorted(i, s.select)

"""
Obtain an iterable through all nodes indices in the parent class.
"""
indices(::Restriction) = throw("unimplemented")
indices(f::Full) = 1:f.n
indices(r::Range) = r.range
indices(s::Sparse) = s.select

"""
Convert a local index to a parent index.
"""
toparent(::Int, ::Restriction) = throw("unimplemented")
toparent(i::Int, ::Full) = i
toparent(i::Int, r::Range) = i + first(r.range) - 1
toparent(i::Int, s::Sparse) = s.select[i]
