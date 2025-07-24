"""
One class in the classes hierarchy trees,
specifying how it restricts nodes from its parents class,
and holding associated data: only vectors whose size match the class size.
"""
struct Class{R<:Restriction}
    name::Symbol
    parent::Option{Class}
    restriction::R
    index::Dict{Symbol,Int}
    data::Dict{Symbol,Entry{<:Vector}}
end

"""
Construct root class.
"""
Class(name) = Class(name, nothing, Full(0), Dict(), Dict())

"""
Construct a subclass.
"""
function Class(name, parent::Class, r::Restriction)
    index = Dict(label => i for (label, i) in parent.index)
    Class(name, parent, r, index, Dict())
end

# HERE: implement primitives.
