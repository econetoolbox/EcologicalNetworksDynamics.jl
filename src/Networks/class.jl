"""
One class in the classes hierarchy trees,
specifying how it restricts nodes from its parents class,
and holding associated data: only vectors whose size match the class size.
"""
struct Class{R<:Restriction}
    name::Symbol
    parent::Option{Class}
    restriction::R
    index::OrderedDict{Symbol,Int}
    data::Dict{Symbol,Entry{<:Vector}}
end

"""
Construct root class.
"""
Class(name) = Class(name, nothing, Full(0), OrderedDict(), Dict())

"""
Construct a subclass.
"""
function Class(name, parent::Class, r::Restriction)
    index = OrderedDict(label => i for (label, i) in parent.index)
    Class(name, parent, r, index, Dict())
end

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
