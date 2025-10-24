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
Total number of edges in the network.
"""
n_edges(n::Network) = sum(n_edges(web.topology) for web in values(n.webs); init = 0)
export n_edges

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

    if nc + nw + nf == 1 # Only the root class?
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
        sorted = [:root]
        sorted = append!(sorted, sort(collect(k for k in keys(net.classes) if k != :root)))
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
