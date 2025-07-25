"""
The core exposed type in this module,
responsible for owning all network data.
See module documentation for detail.
"""
mutable struct Network
    # Node-level data.
    root::Class{Full} # Entry point.
    classes::Dict{Symbol,Class}

    # Edge-level data.
    webs::Dict{Symbol,Web}

    # Graph-level data.
    data::Dict{Symbol,Entry}
end
export Network

"""
Construct empty network.
"""
function Network()
    root = Class(:root)
    finalizer(drop!, Network(root, Dict(:root => root), Dict(), Dict()))
end

"""
Fork the network to obtain a cheap COW-py.
"""
function fork(n::Network)
    (; classes, webs, data) = n
    classes, webs, data = fork.((classes, webs, data))
    Network(classes[:root], classes, webs, data)
end
Base.copy(n::Network) = fork(n)
Base.deepcopy(::Network) = throw("Deepcopying the network would break its COW logic.")

"""
Decrease fields ref-counting prior to garbage-collection.
Registered as a finalizer for the network: don't call manually.
"""
drop!(n::Network) =
    for entry in entries(n)
        decref(field(entry))
    end

function entries(n::Network)
    (; classes, webs, data) = n
    I.flatten((
        I.flatten(entries(e) for e in values(classes)),
        I.flatten(entries(e) for e in values(webs)),
        values(data),
    ))
end

# ==========================================================================================
# Query.

"""
Total number of nodes in the network.
"""
n_nodes(n::Network) = sum((n_nodes(c) for c in values(n.classes)); init = 0)
export n_nodes

"""
Total number of fields in the network.
"""
n_fields(n::Network) =
    sum(n_fields(c) for c in values(n.classes); init = 0) +
    sum(n_fields(w) for w in values(n.webs); init = 0) +
    length(n.data)
export n_fields

# ==========================================================================================
# Display.

function Base.show(io::IO, net::Network)
    print(io, "Network(")
    n, s = ns(n_nodes(net))
    print(io, "$n node$s")
    n, s = ns(n_fields(net))
    print(io, " and $n field$s")
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", net::Network)
    print(io, "Network with ")
    nn, s = ns(n_nodes(net))
    print(io, "$nn node$s")
    nf, s = ns(n_fields(net))
    print(io, " and $nf field$s")

    if nn + nf == 0
        print(io, ".")
        return
    else
        print(io, ":")
    end

    ngd = length(net.data)
    if ngd > 0
        prefix(i) = print(io, "\n" * "  "^i)
        prefix(1)
        print(io, "Graph-level data:")
        for (name, entry) in net.data
            prefix(2)
            nnt = nnet(n_networks(entry))
            scan(entry) do value
                print(io, "$name$nnt: $value")
            end
        end
    end

    if nn > 0
        prefix(1)
        print(io, "Node-level data:")
        for class in values(net.classes)
            (; name) = class
            prefix(2)
            print(io, "Class :$name:")
        end
    end

end

# Elide number of aggregates if non-shared.
nnet(n) = n == 1 ? "" : "<$n>" # (display if zero though 'cause it's a bug)

# Basic plural.
ns(n) = (n, n > 1 ? "s" : "")
