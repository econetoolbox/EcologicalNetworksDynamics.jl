"""
One class of nodes in the classes hierarchy trees,
specifying how it restricts nodes from its parents class,
and holding associated data: only vectors whose size match the class size.
"""
struct Class
    # Immutable: alias when forking.
    name::Symbol
    parent::Option{Symbol} # None for root classes.
    restriction::Restriction
    index::Index
    # Append-only with mutable values protected with entries.
    data::Dict{Symbol,Entry{<:Vector}}
end

"""
Construct a subclass.
"""
function Class(name, parent_name::Option{Symbol}, parent_index::Index, r::Restriction)
    Class(name, parent_name, r, Index(parent_index, r), Dict())
end

"""
Fork class, called when COW-pying the whole network.
"""
function fork(c::Class)
    (; name, parent, restriction, index, data) = c
    Class(name, parent, restriction, index, fork(data))
end

# Visit all entries.
entries(c::Class) = values(c.data)

#-------------------------------------------------------------------------------------------
# Base queries.

"""
Number of nodes in the class.
"""
n_nodes(c::Class) = length(c.restriction)
Base.length(c::Class) = n_nodes(c)

"""
Obtain iterable through all nodes labels in the class, in order.
"""
node_labels(c::Class) = keys(c.index)

"""
Obtain iterable through all node indices of the class, in its parent scope.
"""
node_indices(c::Class) = indices(c.restriction)

"""
Number of fields in the class.
"""
n_fields(c::Class) = length(c.data)
