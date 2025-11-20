# ==========================================================================================
# Expanding topology.

#-------------------------------------------------------------------------------------------
# Nodes.

"""
Introduce a new root class of nodes in the network.
"""
function add_class!(n::Network, name::Symbol, labels)
    check_free_name(n, name)
    (; classes) = n

    new_class = mutate!(n.index) do index
        # Collect new labels to update global index.
        n_before = length(index)
        n_new = 0
        for label in labels
            label = Symbol(label)
            label in keys(index) && err("There is already a node labeled :$label.")
            n_new += 1
            index[label] = n_before + n_new
        end
        Class(name, nothing, index, Range(n_before .+ (1:n_new)))
    end

    classes[name] = new_class

    nothing
end
export add_class!

"""
Introduce a new subclass of nodes.
"""
function add_subclass!(n::Network, parent::Symbol, name::Symbol, r::Restriction)
    check_free_name(n, name)
    (; classes) = n
    parent = classes[parent]
    classes[name] = Class(name, parent.name, parent.index, r)
    nothing
end
add_subclass!(n::Network, p::Symbol, c::Symbol, r::Range) = add_subclass!(n, p, c, Range(r))
add_subclass!(n::Network, p::Symbol, c::Symbol, mask) =
    add_subclass!(n, p, c, sparse_from_mask(mask))
export add_subclass!

#-------------------------------------------------------------------------------------------
# Edges.

"""
Introduce new edges in the network by connecting two classes with the given topology.
"""
function add_web!(
    n::Network,
    name::Symbol,
    (source, target)::Tuple{Symbol,Symbol},
    topology::Topology,
)
    check_free_name(n, name)
    (; classes, webs) = n
    for (what, class, exp) in
        (("source", source, n_sources(topology)), ("target", target, n_targets(topology)))
        check_class_name(n, class)
        act = n_nodes(classes[class])
        exp == act || err("Nodes in class :$class: $act, but $exp in topology $(what)s.")
    end
    webs[name] = Web(name, source, target, topology)
    nothing
end
export add_web!

# ==========================================================================================
# Adding data.

"""
Add new graph-level data to the network.
The given value will be moved into a protected Entry/Field:
don't keep references around or leak them to end users.
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
don't keep references around or leak them to end users.
"""
function add_field!(c::Class, fname::Symbol, v::Vector)
    check_value(v)
    (; name, data) = c
    fname in keys(data) && err("Class :$name already contains a field :$fname.")
    (nv, nc) = length.((v, c))
    nv == nc ||
        err("The given vector (size $nv) does not match the :$name class size ($nc).")
    data[fname] = Entry(v)
    nothing
end

"""
Add new data to every edge in the web.
The given vector will be moved into a protected Entry/Field:
don't keep references around or leak them to end users.
"""
function add_field!(w::Web, fname::Symbol, v::Vector)
    check_value(v)
    (; name, data) = w
    fname in keys(data) && err("Web :$name already contains a field :$fname.")
    (nv, nw) = length(v), n_edges(w)
    nv == nw || err("The given vector (size $nv) does not match the :$name web size ($nw).")
    data[fname] = Entry(v)
    nothing
end

# Convenience entrypoint leveraging non-overlapping classe/webs names.
add_field!(n::Network, name::Symbol, fname::Symbol, v::Vector) =
    if name in keys(n.classes)
        add_field!(n.classes[name], fname, v)
    elseif name in keys(n.webs)
        add_field!(n.webs[name], fname, v)
    else
        err("Neither a class name nor a web name: $name.")
    end

# ==========================================================================================
# Extract views into the data.

"""
Get a graph-level view into network data.
"""
function graph_view(n::Network, data::Symbol)
    data in keys(n.data) || err("There is no data :$data in the network.")
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

    V = eltype(entry)
    T = eltype(V)
    NodesView{T}(n, c, entry)
end
export nodes_view

"""
Get an edge-level view into network data.
"""
function edges_view(n::Network, web::Symbol, data::Symbol)
    (; webs) = n
    web in keys(webs) || err("There is no web :$web in the network.")
    w = webs[web]

    data in keys(w.data) || err("There is no data :$data in web :$web.")
    entry = w.data[data]

    V = eltype(entry)
    T = eltype(V)
    EdgesView{T}(n, w, entry)
end
export edges_view

# ==========================================================================================
# Queries.

"""
Using labels, obtain absolute class node indices.
"""
function absolute_indices(n::Network, class::Symbol)
    check_class_name(n, class)
    class = n.classes[class]
    read(n.index) do root_index
        [root_index[label] for label in keys(class.index)]
    end
end
export absolute_indices
