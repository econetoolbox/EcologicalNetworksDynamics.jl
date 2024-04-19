import ..Display: join_elided

s(n) = n > 1 ? "s" : ""
are(n) = n > 1 ? "are" : "is"
function _th(n)
    b, i = n ÷ 10, n % 10
    b == 1 && return "th"
    i == 1 && return "st"
    i == 2 && return "nd"
    i == 3 && return "rd"
    "th"
end
th(n) = "$n$(_th(n))"

function Base.show(io::IO, g::Topology)
    n_nt = n_node_types(g)
    n_et = n_edge_types(g)
    n_n = sum((U.n_nodes(g, i) for i in 1:n_nt); init = 0)
    n_e = sum((U.n_edges(g, i) for i in 1:n_et); init = 0)
    print(
        io,
        "Topology(\
         $n_nt node type$(s(n_nt)), \
         $n_et edge type$(s(n_et)), \
         $n_n node$(s(n_n)), \
         $n_e edge$(s(n_e))\
         )",
    )
end

function Base.show(io::IO, ::MIME"text/plain", g::Topology)
    elision_limit = 16
    n_nt = n_node_types(g)
    n_et = n_edge_types(g)
    n_n = sum((U.n_nodes(g, i) for i in 1:n_nt); init = 0)
    n_e = sum((U.n_edges(g, i) for i in 1:n_et); init = 0)
    print(
        io,
        "Topology for $n_nt node type$(s(n_nt)) \
         and $n_et edge type$(s(n_et)) \
         with $n_n node$(s(n_n)) and $n_e edge$(s(n_e))",
    )
    if n_n > 0
        print(io, ":")
    else
        print(".")
    end
    println(io, "\n  Nodes:")
    for (i_type, type) in enumerate(_node_types(g))
        i_type > 1 && println(io)
        live = Symbol[]
        tomb = Symbol[] # Collect removed nodes to display at the end.
        for i_node in U.nodes_abs_indices(g, i_type)
            node = U.node_label(g, i_node)
            if U.is_removed(g, i_node)
                push!(tomb, node)
                continue
            end
            push!(live, node)
        end
        print(io, "    $(repr(type)) => [$(join_elided(live, ", "; max =elision_limit))]")
        if !isempty(tomb)
            print(io, "  <removed: [$(join_elided(tomb, ", "; max=elision_limit))]>")
        end
    end
    n_e > 0 && print(io, "\n  Edges:")
    for (i_type, type) in enumerate(_edge_types(g))
        print(io, "\n    $(repr(type))")
        display_line(src, targets) = print(
            io,
            "\n      $(repr(src)) => [$(join_elided(targets, ", "; max=elision_limit))]",
        )
        last = nothing # Save last in case we use vertical elision.
        i = 0
        for (i_source, _neighbours) in U._outgoing_adjacency(g, i_type)
            i += 1
            isempty(_neighbours) && continue
            source = U.node_label(g, Abs(i_source))
            targets = sort(collect(imap(i -> U.node_label(g, Abs(i)), _neighbours)))
            if i <= elision_limit
                display_line(source, targets)
            end
            last = (source, targets)
        end
        if isnothing(last)
            print(io, " <none>")
        end
        if i > elision_limit
            print(io, "\n      ...")
        end
        if i >= elision_limit
            (source, targets) = last
            display_line(source, targets)
        end
    end
end

# A debug display to just screen through the whole value.
debug(g::Topology) =
    for fn in fieldnames(Topology)
        val = getfield(g, fn)
        if fn in (:incoming, :outgoing)
            println("$fn: ")
            for (i_adj, adj) in enumerate(val)
                print("  $i_adj: ")
                if adj isa Tombstone
                    println("<tombstone>")
                    continue
                end
                for (i_et, et) in enumerate(adj)
                    print("\n    $i_et: $([i for i in et])")
                end
                println()
            end
        else
            println("$fn: $val")
        end
    end
