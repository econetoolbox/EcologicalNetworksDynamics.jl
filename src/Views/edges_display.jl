function inline_info(v::EdgesView)
    web = V.web(v).name
    field = fieldname(v)
    "<$web:$field>"
end

function display_info(v::EdgesView)
    T = eltype(v)
    info = inline_info(v)
    "EdgesView$info{$T}"
end

type_info(::Type{<:EdgesView}) = "edges"

function Base.show(io::IO, v::EdgesView)
    print(io, inline_info(v))
    raw = entry(v)
    l, (m, n) = length(v), size(v)
    if l == 0
        print(io, "($m×$n: no values)")
    elseif l == 1
        (x,) = read(identity, raw)
        print(io, "($m×$n: 1 value: $x)")
    else
        min, max = read(minmax, entry(v))
        print(io, "($m×$n: $l values ranging from $min to $max)")
    end
end

function Base.show(io::IO, ::MIME"text/plain", v::EdgesView)
    print(io, display_info(v))
    l, (m, n) = length(v), size(v)
    l, s = ns(l)
    top = topology(v)
    print(io, " ($m×$n: $l value$s)")
    widths = zeros(Int, n)
    lines = []
    view = V.view(v)
    for i in 1:m
        line = []
        for j in 1:n
            f = if is_edge(top, i, j)
                x = view[(i, j)]
                repr(x)
            else
                "·"
            end
            w = length(f)
            widths[j] < w && (widths[j] = w)
            push!(line, f)
        end
        push!(lines, line)
    end
    for line in lines
        print(io, '\n')
        for (value, width) in zip(line, widths)
            print(io, ' ' * lpad(value, width))
        end
    end
end
