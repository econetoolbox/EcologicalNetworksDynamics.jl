#-------------------------------------------------------------------------------------------
# Expanding topology.

"""
Introduce new nodes in the network by extending the root class.
The class produced is a direct children of the root class.
"""
function add_class!(n::Network, name::Symbol, labels)
    (; classes) = n
    name in keys(classes) && err("There is already a class named :$name.")
    root = classes[:root]

    # Collect new labels.
    n_before = n_nodes(n)
    n_new = mutate!(root.index) do index
        n_new = 0
        for label in labels
            label = Symbol(label)
            label in keys(index) && err("There is alread a node labeled :$label.")
            n_new += 1
            index[label] = n_before + n_new
        end
        n_new
    end

    # Increase root class size.
    full = root.restriction
    mutate!(full) do full
        full.n += n_new
    end

    # Construct new base class.
    classes[name] = Class(name, root, Range(n_before .+ (1:n_new)))

    nothing
end
export add_class!

"""
Introduce a new subclass of nodes.
"""
function add_subclass!(n::Network, parent::Symbol, name::Symbol, r::Restriction)
    (; classes) = n
    name in keys(classes) && err("There is already a class named :$name.")
    parent = classes[parent]
    classes[name] = Class(name, parent, r)
    nothing
end
add_subclass!(n::Network, p::Symbol, c::Symbol, r::Range) = add_subclass!(n, p, c, Range(r))
add_subclass!(n::Network, p::Symbol, c::Symbol, mask) =
    add_subclass!(n, p, c, sparse_from_mask(mask))
export add_subclass!

#-------------------------------------------------------------------------------------------
# Adding data.

"""
Add new graph-level data to the network.
The given value will be moved into a protected Entry/Field:
don't keep reference around or leak them to end users.
"""
function add_field!(n::Network, fname::Symbol, v)
    check_value(v)
    fname in keys(n.data) && err("Network already contains a field :$fname.")
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
    fname in keys(data) && err("Class :$name already contains a field :$fname.")
    (nv, nc) = length.((v, c))
    nv == nc || err("The given vector (size $nv) does not match the class size ($nc).")
    data[fname] = Entry(v)
    nothing
end
add_field!(n::Network, cname::Symbol, fname::Symbol, v::Vector) =
    add_field!(n.classes[cname], fname, v)
export add_field!

# All network data must be meaningfully copyable for COW to make sense.
function check_value(value)
    T = typeof(value)
    hasmethod(deepcopy, (T,)) || err("Cannot add non-deepcopy field:\n$value ::$T")
end

#-------------------------------------------------------------------------------------------
# Extract views into the data.

"""
Get a graph-level view into network data.
"""
function graph_view(n::Network, data::Symbol)
    data in keys(n.data) || err("There is no data :$data in network.")
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
    class in keys(classes) || err("There is no class :$class in the network.")
    c = classes[class]

    data in keys(c.data) || err("There is no data :$data in class :$class.")
    entry = c.data[data]

    R = restrict_type(c)
    V = eltype(entry)
    T = eltype(V)
    NodesView{T,R}(c, entry)
end
export nodes_view
