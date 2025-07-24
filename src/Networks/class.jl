"""
One class in the classes hierarchy trees,
specifying how it restricts nodes from its parents class,
and holding associated data: only vectors whose size match the class size.
"""
struct Class{R<:Restriction}
    name::Symbol
    parent::Option{Class}
    restriction::Entry{R}
    index::Entry{Index}
    data::Dict{Symbol,Entry{<:Vector}}
end
restrict_type(::Class{R}) where {R} = R
Class(c::Class) = fork(c)

"""
Construct root class.
"""
Class(name) = Class(name, nothing, Entry{Full}(Full(0)), Entry{Index}{Index()}, Dict())

"""
Construct a subclass.
"""
function Class(name, parent::Class, r::Restriction)
    R = typeof(r)
    index = Index(label => i for (label, i) in parent.index)
    Class(name, parent, Entry{R}(r), Entry{Index}(index), Dict())
end

"""
Fork class, called when COW-pying the whole network.
"""
function fork(c::Class)
    (; name, parent, restriction, index, data) = c
    Class(name, parent, fork(restriction), fork(index), fork(data))
end

# Visit all entries.
entries(c::Class) = I.flatten((c.restriction, c.index), values(c.data))

#-------------------------------------------------------------------------------------------
# Base queries.

"""
Number of nodes in the class.
"""
Base.length(c::Class) = length(c.restriction)

"""
Parent of the class (or itself if root class).
"""
Base.parent(c::Class) = isnothing(c.parent) ? c : c.parent

"""
Obtain iterable through all nodes labels in the class, in order.
"""
node_labels(c::Class) = keys(c.index)

"""
Obtain iterable through all node indices of the class, in its parent scope.
"""
node_indices(c::Class) = indices(c.restriction)
