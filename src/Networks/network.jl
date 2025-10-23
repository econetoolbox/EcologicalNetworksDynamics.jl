"""
The core exposed type in this module,
responsible for owning all network data.
See module documentation for detail.
"""
mutable struct Network
    # Node-level data.
    root::Class # Entry point.
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
        I.flatten(entries(c) for c in values(classes)),
        I.flatten(entries(w) for w in values(webs)),
        values(data),
    ))
end

# ==========================================================================================
# Query.

"""
Total number of nodes in the network.
"""
n_nodes(n::Network) = n_nodes(n.root)
export n_nodes

"""
Total number of fields in the network.
"""
n_fields(n::Network) =
# https://julialang.zulipchat.com/#narrow/channel/137791-general/topic/type.20inference.20in.20.60sum.60/near/546657153
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

    prefix(i) = print(io, "\n" * "  "^i)

    ngd = length(net.data)
    if ngd > 0
        prefix(1)
        print(io, "Graph:")
        for (name, entry) in net.data
            prefix(2)
            nnt = nnet(n_networks(entry))
            print(io, "$name$nnt: ")
            read(entry) do value
                print(io, value)
            end
        end
    end

    if nn > 0
        prefix(1)
        print(io, "Nodes:")
        sorted = sort(collect(keys(net.classes))) # Consistent output for snapshot-testing.
        for name in sorted
            class = net.classes[name]
            prefix(2)
            print(io, "$name")
            if name != :root
                n = n_nodes(class)
                labels = read(class.index) do index
                    sort(collect(keys(index)))
                end
                labels = join_elided(labels, ", ")
                print(io, " ($n): [$labels]")
            else
                print(io, ":")
                if length(class.data) == 0
                    print(io, " <no data>")
                end
            end
            dsorted = sort(collect(keys(class.data)))
            for name in dsorted
                entry = class.data[name]
                prefix(3)
                nnt = nnet(n_networks(entry))
                print(io, "$name$nnt: ")
                read(entry) do e
                    print(io, e)
                end
            end
        end
    end

end

# Elide number of networks if non-shared.
nnet(n) = n == 1 ? "" : "'$n" # (display if zero though 'cause it's a bug)

# Basic plural.
ns(n) = (n, n > 1 ? "s" : "")
