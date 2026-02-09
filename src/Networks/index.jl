"""
Two-ways conversions between nodes references as integer indices or label symbols.
"""
struct Index
    forward::OrderedDict{Symbol,Int}
    reverse::Vector{Symbol}
    Index() = new(OrderedDict(), [])
    Index(f, r) = new(f, r)
end
S = Index
Base.keys(v::S) = keys(v.forward)
Base.length(v::S) = length(v.forward)
fork(v::Index) = Index(copy(v.forward), copy(v.reverse))
labels(v::S) = keys(v.forward)
label(v::S, i::Int) = v.reverse[i]
export label

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
