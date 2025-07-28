"""
One class in the classes hierarchy trees,
specifying how it restricts nodes from its parents class,
and holding associated data: only vectors whose size match the class size.
"""
struct Class
    name::Symbol
    parent::Option{Class}
    restriction::Entry{<:Restriction}
    index::Entry{Index}
    data::Dict{Symbol,Entry{<:Vector}}
end

"""
Construct root class.
"""
Class(name) = Class(name, nothing, Entry(Full(0)), Entry(Index()), Dict())

"""
Construct a subclass.
"""
function Class(name, parent::Class, r::Restriction)
    # Construct local index.
    index = read(parent.index) do index
        loc = Index()
        i_local = 0
        for (label, i_parent) in index
            i_parent in r || continue
            i_local += 1
            loc[label] = i_local
        end
        loc
    end
    Class(name, parent, Entry(r), Entry(index), Dict())
end

"""
Fork class, called when COW-pying the whole network.
"""
function fork(c::Class)
    (; name, parent, restriction, index, data) = c
    Class(name, parent, fork(restriction), fork(index), fork(data))
end

# Visit all entries.
entries(c::Class) = I.flatten(((c.restriction, c.index), values(c.data)))

#-------------------------------------------------------------------------------------------
# Base queries.

"""
Number of nodes in the class.
"""
n_nodes(c::Class) = read(length, c.restriction)
Base.length(c::Class) = n_nodes(c)

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

"""
Number of fields in the class.
"""
n_fields(c::Class) = length(c.data)
