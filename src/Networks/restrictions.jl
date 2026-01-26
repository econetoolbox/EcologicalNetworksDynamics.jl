"""
Specify how nodes are filtered or "restricted"
from one class to its subclass.
"""
abstract type Restriction end
export Restriction

# ==========================================================================================
# The various kinds of restrictions.

"""
Root class 'no-restriction', including all nodes in canonical order.
"""
struct Full <: Restriction
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
Restrict with a sparse list of ranges.
"""
struct SparseRanges <: Restriction
    # Disjoint, sorted and *compact* in that adjacent ranges have been merged together.
    ranges::Vector{UnitRange{Int}}
    cumsizes::Vector{Int} # Useful for efficient to_parent query.
    SparseRanges(ranges) = new(ranges, cumsum(I.map(length, ranges)))
end

#-------------------------------------------------------------------------------------------
# Query restrictions.

"""
Number of nodes in the restriction.
"""
Base.length(::Restriction) = throw("unimplemented")
Base.length(f::Full) = f.n
Base.length(r::Range) = length(r.range)
Base.length(s::Sparse) = length(s.select)
Base.length(s::SparseRanges) = last(s.cumsizes)

"""
Given an index *from the parent class*,
query whether it also belongs to the restricted subclass.
"""
Base.in(::Int, ::Restriction) = throw("unimplemented")
Base.in(::Int, ::Full) = true
Base.in(i::Int, r::Range) = i in r.range
Base.in(i::Int, s::Sparse) = insorted(i, s.select)
function Base.in(i::Int, (; ranges)::SparseRanges)
    s = searchsortedfirst(ranges, i:i; lt = (a, b) -> last(a) < first(b))
    i in ranges[s]
end

"""
Obtain an iterable through all nodes indices in the parent class.
"""
indices(::Restriction) = throw("unimplemented")
indices(f::Full) = 1:f.n
indices(r::Range) = r.range
indices(s::Sparse) = s.select
indices(s::SparseRanges) = I.flatten(s.ranges)

"""
Convert a local index to a parent index.
"""
toparent(::Int, ::Restriction) = throw("unimplemented")
toparent(i::Int, ::Full) = i
toparent(i::Int, r::Range) = i + first(r.range) - 1
toparent(i::Int, s::Sparse) = s.select[i]
toparent(i::Int, s::SparseRanges) =
    let
        cs = s.cumsizes
        i_range = searchsortedfirst(cs, i)
        r = s.ranges[i_range]
        r[length(r)-cs[i_range]+i]
    end

"""
Convert a parent index to a local index, assuming it exists.
"""
tolocal(::Int, ::Restriction) = throw("unimplemented")
tolocal(i::Int, ::Full) = i
tolocal(i::Int, r::Range) = i - first(r.range) + 1
tolocal(i::Int, s::Sparse) = searchsortedfirst(s.select, i)
tolocal(i::Int, s::SparseRanges) =
    let
        (; ranges, cumsizes) = s
        i_range = searchsortedfirst(ranges, i:i; lt = (a, b) -> last(a) < first(b))
        r, c = ranges[i_range], cumsizes[i_range]
        c + i + 1 - length(r) - first(r)
    end

#-------------------------------------------------------------------------------------------
"""
Construct restriction from a boolean mask,
picking whichever type is the most compact.
"""
function restriction_from_mask(mask)
    # Try both ranges and scalars representation,
    # pick the most compact.
    scalars = Int[]
    ranges = UnitRange{Int}[]
    open = nothing
    for (i, m) in enumerate(mask)
        if m
            push!(scalars, i)
            if isnothing(open)
                open = i
            end
        elseif !isnothing(open)
            push!(ranges, open:(i-1))
            open = nothing
        end
    end
    if !isnothing(open)
        push!(ranges, open:length(mask))
    end
    if length(ranges) == 1
        Range(first(ranges))
    elseif length(scalars) <= 3 * length(ranges) # (start + end + cumulative sizes)
        Sparse(scalars)
    else
        SparseRanges(ranges)
    end
end
export restriction_from_mask

# Useful for testing.
function Base.:(==)(a::Sparse, b::Sparse)
    (; select) = a
    select == b.select
end
function Base.:(==)(a::SparseRanges, b::SparseRanges)
    (; ranges, cumsizes) = a
    ranges == b.ranges && cumsizes == b.cumsizes
end

#-------------------------------------------------------------------------------------------
"""
Expand data to data that are sparse within the parent by reversing the restriction.
"""
function expand(T::Type, r::Restriction, parent_size::Int, data)
    res = spzeros(T, parent_size)
    for (i, v) in zip(indices(r), data)
        res[i] = v
    end
    res
end
expand(r::Restriction, size::Int, data::AbstractVector{T}) where {T} =
    expand(T, r, size, data)
export expand

"""
Obtain mask within parent class.
"""
mask(r::Restriction, parent_size::Int) = I.map(i -> i in r, 1:parent_size)
export mask
