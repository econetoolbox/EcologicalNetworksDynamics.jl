function inline_info(v::NodesView)
    class = V.class(v).name
    field = fieldname(v)
    "<$class:$field>"
end

function inline_info(v::ExpandedNodesView)
    class = V.class(v).name
    parent = V.parent(v)
    parent = isnothing(parent) ? ":" : parent
    field = fieldname(v)
    "<$parent:$class:$field>"
end

function display_info(v::NodesView)
    T = eltype(v)
    info = inline_info(v)
    "NodesView$info{$T}"
end

function display_info(v::ExpandedNodesView)
    T = eltype(v)
    info = inline_info(v)
    "ExpandedNodesView$info{$T}"
end

type_info(::Type{<:NodesView}) = "nodes"
type_info(::Type{<:ExpandedNodesView}) = "sparse nodes"

function Base.show(io::IO, v::NodesView)
    print(io, inline_info(v))
    print(io, '[')
    read(entry(v)) do raw
        for (i, v) in enumerate(raw)
            print(io, repr(v))
            if i < length(raw)
                print(io, ", ")
            end
        end
    end
    print(io, ']')
end

function Base.show(io::IO, v::ExpandedNodesView)
    print(io, inline_info(v))
    print(io, '[')
    n = length(v)
    mask = N.mask(network(v), class(v).name, parent(v))
    read(entry(v)) do raw
        i_raw = 0
        for (i_m, m) in enumerate(mask)
            if m
                i_raw += 1
                v = raw[i_raw]
                print(io, repr(v))
            else
                print(io, '·')
            end
            if i_m < n
                print(io, ", ")
            end
        end
    end
    print(io, ']')
end

function Base.show(io::IO, ::MIME"text/plain", v::NodesView)
    print(io, display_info(v))
    (n, s) = ns(length(v))
    print(io, " ($n value$s)")
    read(entry(v)) do raw
        for v in raw
            print(io, "\n ")
            print(io, repr(v))
        end
    end
end

function Base.show(io::IO, ::MIME"text/plain", v::ExpandedNodesView)
    print(io, display_info(v))
    mask = N.mask(network(v), class(v).name, parent(v))
    (n, _) = ns(length(v))
    read(entry(v)) do raw
        (nz, s) = ns(length(raw))
        print(io, " ($nz/$n value$s)")
        i_raw = 0
        for m in mask
            print(io, '\n')
            if m
                i_raw += 1
                v = raw[i_raw]
                print(io, repr(v))
            else
                print(io, '·')
            end
        end
    end
end

ns(n) = (n, n > 1 ? "s" : "")
