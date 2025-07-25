#-------------------------------------------------------------------------------------------
# Expanding topology.

"""
Introduce a new class of nodes.
"""
function add_class!(n::Network, parent::Symbol, name::Symbol, r::Restriction)
    (; classes) = n
    name in keys(classes) && argerr("There is already a class named :$name.")
    parent = classes[parent]
    classes[name] = Class(name, parent, r)
    nothing
end
add_class!(n::Network, p::Symbol, c::Symbol, r::Range) = add_class!(n, p, c, Range(r))
add_class!(n::Network, p::Symbol, c::Symbol, mask) =
    add_class!(n, p, c, sparse_from_mask(mask))
export add_class!

#-------------------------------------------------------------------------------------------
# Adding data.

"""
Add new graph-level data to the network.
The given value will be moved into a protected Entry/Field:
don't keep reference around or leak them to end users.
"""
function add_field!(n::Network, fname::Symbol, v)
    check_value(v)
    fname in keys(n.data) && argerr("Network already contains a field :$fname.")
    n.data[fname] = Entry(v)
    nothing
end
export add_field!

"""
Add new data to every node in the class.
The given vector will be moved into a protected Entry/Field:
don't keep reference around or leak them to end users.
"""
function add_field!(c::Class, fname::Symbol, v::Vector)
    check_value(v)
    (; name, data) = c
    fname in keys(data) && argerr("Class :$name already contains a field :$fname.")
    (nv, nc) = length((v, c))
    nv == nc || argerr("The given vector (size $nv) does not match the class size ($nc).")
    data[name] = Entry(v)
    nothing
end
export add_field!

# All network data must be meaningfully copyable for COW to make sense.
function check_value(value)
    T = typeof(value)
    hasmethod(deepcopy, (T,)) || argerr("Cannot add non-deepcopy field:\n$value ::$T")
end

#-------------------------------------------------------------------------------------------
# Extract views into the data.

"""
Get a graph-level view into network data.
"""
function graph_view(n::Network, data::Symbol)
    data in keys(n.data) || argerr("There is no data :$data in network.")
    entry = n.data[data]
    T = eltype(entry)
    GraphView{T}(n, entry)
end
export graph_view

"""
Get a node-level view into network data.
"""
function nodes_view(n::Network, class::Symbol, data::Symbol)
    (; classes) = n
    class in keys(classes) || argerr("There is no class :$class in the network.")
    c = classes[class]

    data in keys(c.data) || argerr("There is no data :$data in class :$class.")
    entry = c.data[data]

    R = restrict_type(c)
    T = eltype(entry)
    NodesView{T,R}(c, entry)
end
export nodes_view
