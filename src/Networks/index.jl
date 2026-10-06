"""
Two-ways conversions between nodes references as integer indices or label symbols.
"""
struct Index
    forward::OrderedDict{Symbol,Int} # {label ↦ index}
    reverse::Vector{Symbol} # {index ↦ label}
    Index() = new(OrderedDict(), [])
    Index(f, r) = new(f, r)
end
S = Index
Base.keys(s::S) = keys(s.forward)
Base.length(s::S) = length(s.forward)
fork(s::Index) = Index(copy(s.forward), copy(s.reverse))
labels(s::S) = keys(s.forward)

# Assuming correct input.
to_index(::S, i::Int) = i
to_label(::S, l::Symbol) = l
to_index(s::S, l::Symbol) = s.forward[l]
to_label(s::S, i::Int) = s.reverse[i]
is_label(s::S, l::Symbol) = haskey(s.forward, l)
is_index(s::S, i::Int) = 1 <= i <= length(s)
is_ref(s::S, i::Int) = is_index(s, i)
is_ref(s::S, l::Symbol) = is_label(s, l)

"""
Build from a parent index and a restriction, assuming they are consistent.
"""
function Index(parent::Index, restriction::Restriction)
    res = Index()
    for (label, i_parent) in parent.forward
        i_parent in restriction || continue
        push!(res.reverse, label)
        res.forward[label] = length(res.reverse)
    end
    res
end
