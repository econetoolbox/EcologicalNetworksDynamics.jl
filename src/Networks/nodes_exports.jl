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
Optionally require grand-parent class instead *etc.*
Use `nothing` for absolute sparsity from root-level perspective.
"""
function to_sparse(v::NodesView)
    T = eltype(v)
    class = Networks.class(v)
    isnothing(class.parent) && err("The root nodes class is not sparse within another.")
    parent = network(v).classes[class.parent]
    res = spzeros(T, n_nodes(parent))
    read(entry(v)) do v
        for (i_local, i_parent) in enumerate(indices(class.restriction))
            res[i_parent] = v[i_local]
        end
    end
    res
end

function to_sparse(v::NodesView, parent_name::Symbol)
    T = eltype(v)
    n = network(v)
    check_class_name(n, parent_name)
    class = Networks.class(v)
    # Find adequate parent class.
    parent = class
    while true
        isnothing(class.parent) &&
            err("Node class :$parent_name does not superclass :$(class.name).")
        parent = n.classes[parent.parent]
        parent.name == parent_name && break
    end
    # Use it to fill the result.
    res = spzeros(T, n_nodes(parent))
    read(entry(v)) do v
        for (label, i_local) in class.index
            i_parent = parent.index[label]
            res[i_parent] = v[i_local]
        end
    end
    res
end

# Absolute.
# HERE: the result must be contiguous then: not exactly useful? Replace with restrictions?
function to_sparse(v::NodesView, ::Nothing)
    T = eltype(v)
    class = Networks.class(v)
    n = network(v)
    res = spzeros(T, n_nodes(n))
    read(entry(v), n.index) do v, root_index
        for (label, i_local) in class.index
            i_root = root_index[label]
            res[i_root] = v[i_local]
        end
    end
    res
end

export to_sparse
