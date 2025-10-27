# Extract regular data from a nodes view.

"""
Obtain a copy of the underlying vector.
The obtained size and order correspond to the associated nodes class.
"""
to_vec(v::NodesView) = read(collect, v)
export to_vec

"""
Obtain a sparse vector
whose size and order correspond to the parent nodes class,
but with only the focal class values set.
Optionally require grand-parent class instead etc.
"""
function to_sparse(v::NodesView)
    T = eltype(v)
    class = Networks.class(v)
    isnothing(class.parent) && err("The root nodes class is not sparse within another.")
    parent = network(v).classes[class.parent]
    res = spzeros(T, n_nodes(parent))
    read(entry(v), class.restriction) do v, r
        for (i_local, i_parent) in enumerate(indices(r))
            res[i_parent] = v[i_local]
        end
    end
    res
end
function to_sparse(v::NodesView, parent_name::Symbol)
    T = eltype(v)
    class = Networks.class(v)
    isnothing(class.parent) && err("The root nodes class is not sparse within another.")
    # Find adequate parent class.
    n = network(v)
    parent = n.classes[class.parent]
    while true
        parent.name == parent_name && break
        isnothing(parent.parent) &&
            err("Node class :$parent_name does not superclass :$(class.name).")
        parent = n.classes[parent.parent]
    end
    # Use it to fill the result.
    res = spzeros(T, n_nodes(parent))
    read(entry(v), class.index, parent.index) do v, local_index, parent_index
        for (label, i_local) in local_index
            i_parent = parent_index[label]
            res[i_parent] = v[i_local]
        end
    end
    res
end
export to_sparse
