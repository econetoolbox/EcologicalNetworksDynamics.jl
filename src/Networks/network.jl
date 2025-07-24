"""
The core exposed type in this module,
responsible for owning all network data.
See module documentation for detail.
"""
struct Network
    # Node-level data.
    root::Class{Full} # Entry point.
    classes::Dict{Symbol,Class{Union{Range,Sparse}}} # Only subclasses.

    # Edge-level data.
    webs::Dict{Symbol,Web}

    # Graph-level data.
    data::Dict{Symbol,Entry}
end
export Network

"""
Construct empty network.
"""
Network() = Network(Class(:root), Dict(), Dict(), Dict())

#-------------------------------------------------------------------------------------------

"""
Introduce a new class of nodes.
"""
function add_class!(n::Network, parent::Symbol, name::Symbol, r::Restriction)
    (; classes) = n
    name in keys(classes) && argerr("There is already a class named :$name.")
    parent = classes[parent]
    classes[name] = Class(name, parent, r)
end
add_class!(n::Network, p::Symbol, c::Symbol, r::Range{Int}) = add_class!(n, p, c, Range(r))
add_class!(n::Network, p::Symbol, c::Symbol, mask) =
    add_class!(n, p, c, sparse_from_mask(mask))
export add_class!
