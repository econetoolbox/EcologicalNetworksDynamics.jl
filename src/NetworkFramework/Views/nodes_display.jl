function inline_info(v::NodesDataView)
    class = classname(v)
    field = fieldname(v)
    "<$class:$field>"
end

function inline_info(v::ExpandedNodesDataView)
    class = classname(v)
    parent = V.parent(v)
    parent = isnothing(parent) ? ":" : parent
    field = fieldname(v)
    "<$parent:$class:$field>"
end

function inline_info(v::NodesNamesView)
    class = classname(v)
    "<$class>"
end

function inline_info(v::NodesMaskView)
    class = classname(v)
    parent = V.parent(v)
    parent = isnothing(parent) ? ":" : parent
    "<$parent:$class>"
end

function display_info(v::NodesDataView)
    T = eltype(v)
    info = inline_info(v)
    "NodesDataView$info{$T}"
end

function display_info(v::ExpandedNodesDataView)
    T = eltype(v)
    info = inline_info(v)
    "ExpandedNodesDataView$info{$T}"
end

function display_info(v::NodesNamesView)
    T = eltype(v)
    info = inline_info(v)
    "NodesNamesView$info{$T}"
end

function display_info(v::NodesMaskView)
    T = eltype(v)
    info = inline_info(v)
    "NodesMaskView$info{$T}"
end

type_info(::Type{<:NodesDataView}) = "nodes"
type_info(::Type{<:ExpandedNodesDataView}) = "sparse nodes"
type_info(::Type{<:NodesNamesView}) = "nodes names"
type_info(::Type{<:NodesMaskView}) = "nodes mask"

function Base.show(io::IO, v::NodesDataView)
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

function Base.show(io::IO, v::ExpandedNodesDataView)
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

function Base.show(io::IO, v::NodesNamesView)
    print(io, inline_info(v))
    print(io, '[')
    for (i, name) in enumerate(index(v).reverse)
        print(io, repr(name))
        if i < length(v)
            print(io, ", ")
        end
    end
    print(io, ']')
end

function Base.show(io::IO, v::NodesMaskView)
    print(io, inline_info(v))
    print(io, '[')
    n = length(v)
    r = restriction(v)
    for i_parent in 1:n
        if i_parent in r
            print(io, '1')
        else
            print(io, '·')
        end
        if i_parent < n
            print(io, ", ")
        end
    end
    print(io, ']')
end

function Base.show(io::IO, ::MIME"text/plain", v::NodesDataView)
    print(io, display_info(v))
    n, s = ns(length(v))
    w = readonly(v) ? " readonly" : ""
    print(io, " ($n$w value$s)")
    read(entry(v)) do raw
        for v in raw
            print(io, "\n ")
            print(io, repr(v))
        end
    end
end

function Base.show(io::IO, ::MIME"text/plain", v::ExpandedNodesDataView)
    print(io, display_info(v))
    mask = N.mask(network(v), class(v).name, parent(v))
    n, _ = ns(length(v))
    w = readonly(v) ? " (readonly)" : ""
    read(entry(v)) do raw
        (nz, s) = ns(length(raw))
        print(io, " ($nz/$n$w value$s)")
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

function Base.show(io::IO, ::MIME"text/plain", v::NodesNamesView)
    print(io, display_info(v))
    n, s = ns(length(v))
    print(io, " ($n value$s)")
    for name in index(v).reverse
        print(io, "\n ")
        print(io, repr(name))
    end
end

function Base.show(io::IO, ::MIME"text/plain", v::NodesMaskView)
    print(io, display_info(v))
    r = restriction(v)
    n, _ = ns(length(v))
    (nr, s) = ns(length(r))
    print(io, " ($nr/$n value$s)")
    for i_parent in 1:n
        print(io, "\n ")
        print(io, i_parent in r ? '1' : '·')
    end
end

ns(n) = (n, n > 1 ? "s" : "")
