function inline_info(v::NodeFieldView)
    class = D.class(v)
    field = D.field(v)
    "<$class:$field>"
end

function inline_info(v::NodeNameView)
    class = D.class(v)
    "<$class>"
end

function inline_info(v::NodeMaskView)
    class = D.class(v)
    parent = D.parent(v)
    parent = isnothing(parent) ? "·" : parent
    "<$parent:$class>"
end

const fc, rs = F.field_color, reset

function display_info(v::NodeFieldView)
    T = eltype(v)
    info = inline_info(v)
    "NodeFieldView$fc$info$rs{$T}"
end

function display_info(v::NodeNameView)
    T = eltype(v)
    info = inline_info(v)
    "NodeNameView$fc$info$rs{$T}"
end

function display_info(v::NodeMaskView)
    T = eltype(v)
    info = inline_info(v)
    "NodeMaskView$fc$info$rs{$T}"
end

type_info(::Type{<:NodeFieldView}) = "nodes"
type_info(::Type{<:NodeNameView}) = "nodes names"
type_info(::Type{<:NodeMaskView}) = "nodes mask"
type_info(v::AbstractView) = type_info(typeof(v))

function Base.show(io::IO, v::NodeFieldView)
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

function Base.show(io::IO, v::NodeNameView)
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

function Base.show(io::IO, v::NodeMaskView)
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

function Base.show(io::IO, ::MIME"text/plain", v::NodeFieldView)
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

function Base.show(io::IO, ::MIME"text/plain", v::NodeNameView)
    print(io, display_info(v))
    n, s = ns(length(v))
    print(io, " ($n value$s)")
    for name in N.index(v).reverse
        print(io, "\n ")
        print(io, repr(name))
    end
end

function Base.show(io::IO, ::MIME"text/plain", v::NodeMaskView)
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
