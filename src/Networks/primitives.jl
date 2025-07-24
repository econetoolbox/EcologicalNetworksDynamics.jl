"""
Introduce a new class of nodes.
"""
function add_class!(n::Network, parent::Symbol, name::Symbol, r::Restriction)
    (; classes) = n
    name in keys(classes) && argerr("There is already a class named :$name.")
    parent = classes[parent]
    classes[name] = Class(name, parent, r)
end
add_class!(n::Network, p::Symbol, c::Symbol, r::Range) = add_class!(n, p, c, Range(r))
add_class!(n::Network, p::Symbol, c::Symbol, mask) =
    add_class!(n, p, c, sparse_from_mask(mask))
export add_class!

"""
Add new data to every node in the class.
The given vector will be moved into a protected Entry/Field:
don't keep reference around or leak them to end users.
"""
function add_field!(c::Class, fname::Symbol, v::Vector{T}) where {T}

    # The data needs to be meaningfully copyable for the COW to work.
    hasmethod(deepcopy, (T,)) || argerr("Cannot add non-deepcopy field.")

    (; name, data) = c
    fname in keys(data) && argerr("Class :$name already contains a field :$fname.")

    (nv, nc) = length((v, c))
    nv == nc || argerr("The given vector (size $nv) does not match the class size ($nc).")

    V = Vector{T}
    data[name] = Entry{V}(Field{V}(v))
end
export add_field!

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
    T = eltype(data)
    View{R,T}(entry, c)
end
export view
