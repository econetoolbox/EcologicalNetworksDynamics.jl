function inline_info(v::NodesDataView)
    class = D.class(v)
    field = D.field(v)
    "<$class:$field>"
end

function inline_info(v::SparseNodesDataView)
    class = D.class(v)
    parent = D.parent(v)
    parent = isnothing(parent) ? ":" : parent
    field = D.field(v)
    "<$parent:$class:$field>"
end

function inline_info(v::NodesNamesView)
    class = D.class(v)
    "<$class>"
end

function inline_info(v::NodesMaskView)
    class = D.class(v)
    parent = D.parent(v)
    parent = isnothing(parent) ? ":" : parent
    "<$parent:$class>"
end

function display_info(v::NodesDataView)
    T = eltype(v)
    info = inline_info(v)
    "NodesDataView$info{$T}"
end

function display_info(v::SparseNodesDataView)
    T = eltype(v)
    info = inline_info(v)
    "SparseNodesDataView$info{$T}"
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
type_info(::Type{<:SparseNodesDataView}) = "sparse nodes"
type_info(::Type{<:NodesNamesView}) = "nodes names"
type_info(::Type{<:NodesMaskView}) = "nodes mask"

function Base.show(io::IO, v::NodesDataView)
    print(io, inline_info(v))
    print(io, '[')
    read(N.entry(v)) do raw
        for (i, v) in enumerate(raw)
            print(io, repr(v))
            if i < length(raw)
                print(io, ", ")
            end
        end
    end
    print(io, ']')
end

function Base.show(io::IO, v::SparseNodesDataView)
    print(io, inline_info(v))
    print(io, '[')
    n = length(v)
    mask = N.mask(N.network(v), D.class(v), D.parent(v))
    read(N.entry(v)) do raw
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
    for (i, name) in enumerate(N.index(v).reverse)
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
    r = N.restriction(v)
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
    w = D.readonly(v) ? " readonly" : ""
    print(io, " ($n$w value$s)")
    read(N.entry(v)) do raw
        for v in raw
            print(io, "\n ")
            print(io, repr(v))
        end
    end
end

function Base.show(io::IO, ::MIME"text/plain", v::SparseNodesDataView)
    print(io, display_info(v))
    mask = N.mask(N.network(v), D.class(v), D.parent(v))
    n, _ = ns(length(v))
    w = D.readonly(v) ? " (readonly)" : ""
    read(N.entry(v)) do raw
        (nz, s) = ns(length(raw))
        print(io, " ($nz/$n$w value$s)")
        i_raw = 0
        for m in mask
            print(io, "\n ")
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
    for name in N.index(v).reverse
        print(io, "\n ")
        print(io, repr(name))
    end
end

function Base.show(io::IO, ::MIME"text/plain", v::NodesMaskView)
    print(io, display_info(v))
    r = N.restriction(v)
    n, _ = ns(length(v))
    (nr, s) = ns(length(r))
    print(io, " ($nr/$n value$s)")
    for i_parent in 1:n
        print(io, "\n ")
        print(io, i_parent in r ? '1' : '·')
    end
end

ns(n) = (n, n > 1 ? "s" : "")
