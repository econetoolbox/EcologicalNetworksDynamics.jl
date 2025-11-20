"""
The core exposed type in this module,
responsible for owning all network data.
See module documentation for detail.
"""
mutable struct Network
    # Global 'root' node index: append-only.
    index::Entry{Index}

    # Node-level data: append-only.
    classes::Dict{Symbol,Class}

    # Edge-level data: append-only.
    webs::Dict{Symbol,Web}

    # Graph-level data: append-only.
    data::Dict{Symbol,Entry}

    # Cache requested restriction beyond simple parent-to-child classes,
    # but also grandparents *etc.*
    # This only makes sense because the whole topology is append-only,
    # so restrictions here must never be invalidated.
    # { (child, [grand-]+parent): restriction }
    restrictions::Dict{Tuple{Symbol,Option{Symbol}},Entry{<:Restriction}}
end
export Network

"""
Construct empty network.
"""
Network() = finalizer(drop!, Network(Entry(Index()), Dict(), Dict(), Dict(), Dict()))

"""
Fork the network to obtain a cheap COW-py.
"""
function fork(n::Network)
    (; index, classes, webs, data, restrictions) = n
    index, classes, webs, data, restrictions =
        fork.((index, classes, webs, data, restrictions))
    Network(index, classes, webs, data, restrictions)
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
Extract web or class.
"""
class(n::Network, name::Symbol) = n.classes[name]
web(n::Network, name::Symbol) = n.webs[name]
export class, web

"""
Total number of nodes in the network,
or in the given class.
"""
n_nodes(n::Network) = read(length, n.index)
n_nodes(n::Network, class::Symbol) = n_nodes(Networks.class(n, class))
export n_nodes

"""
Total number of edges in the network,
or in the given web.
"""
n_edges(n::Network) = sum(n_edges(web.topology) for web in values(n.webs); init = 0)
n_edges(n::Network, web::Symbol) = n_edges(Networks.web(n, web).topology)
export n_edges

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
    with = []
    nn, s = ns(n_nodes(net))
    if nn > 0
        push!(with, "$nn node$s")
    end

    ne, s = ns(n_edges(net))
    if ne > 0
        push!(with, "$ne edge$s")
    end
    nf, s = ns(n_fields(net))
    if nf > 0
        push!(with, "$nf field$s")
    end

    nc = length(net.classes)
    nw = length(net.webs)

    if nc + nw + nf == 0
        print(io, "Empty network.")
        return
    else
        print(io, "Network with $(join(with, ", ", " and ")):")
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

    print_data(data) = begin
        dsorted = sort(collect(keys(data)))
        for name in dsorted
            entry = data[name]
            prefix(3)
            nnt = nnet(n_networks(entry))
            print(io, "$name$nnt: ")
            read(entry) do e
                print(io, e)
            end
        end
    end

    if nn > 0
        prefix(1)
        print(io, "Nodes:")
        sorted = sort(collect(k for k in keys(net.classes)))
        for name in sorted
            class = net.classes[name]
            prefix(2)
            print(io, "$name")
            if name != :root
                n = n_nodes(class)
                labels = sort(collect(keys(class.index)))
                labels = join_elided(labels, ", ")
                print(io, " ($n): [$labels]")
            else
                print(io, ":")
                if length(class.data) == 0
                    print(io, " -")
                end
            end
            print_data(class.data)
        end
    end

    if ne > 0
        prefix(1)
        print(io, "Edges:")
        sorted = sort(collect(keys(net.webs)))
        for name in sorted
            web = net.webs[name]
            prefix(2)
            n = n_edges(web)
            props = ["$n"]
            if web.topology isa SymmetricTopology
                push!(props, "symmetric")
            end
            if web.topology isa SparseTopology
                push!(props, "sparse")
            else
                push!(props, "full")
            end
            src, tgt = web.source, web.target
            print(io, "$name: $src => $tgt ($(join(props, ", ")))")
            print_data(web.data)
        end
    end

end

# Elide number of networks if non-shared.
nnet(n) = n == 1 ? "" : "'$n" # (display if zero though 'cause it's a bug)

# Basic plural.
ns(n) = (n, n == 1 ? "" : "s")
