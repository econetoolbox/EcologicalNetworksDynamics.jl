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
Network() = finalizer(drop!, Network(Class(:root), Dict(), Dict(), Dict()))

"""
Fork the network to obtain a cheap COW-py.
"""
function fork(n::Network)
    (; root, classes, webs, data) = n
    Network(
        fork(root),
        Dict(n => fork(c) for (n, c) in classes),
        Dict(n => fork(w) for (n, w) in webs),
        fork(data),
    )
end
Base.copy(n::Network) = fork(n)
Base.deepcopy(::Network) = throw("Deepcopying the network would break its COW logic.")

# Decrease fields ref-counting prior to garbage-collection.
# Registered as a finalizer for the network: don't call manually.
drop!(n::Network) =
    for entry in entries(n)
        entry.field.n_aggregates -= 1
    end

function entries(n::Network)
    (; root, classes, webs, data) = n
    I.flatten(
        entries(root),
        I.flatten(entries(e) for e in values(classes)),
        I.flatten(entries(e) for e in values(webs)),
        values(data),
    )
end
