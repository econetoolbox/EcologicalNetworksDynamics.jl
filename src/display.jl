module Display

using SparseArrays

using Crayons
for col in [:red, :green, :blue, :cyan, :yellow, :black, :bold, :italics, :reset]
    eval(quote
        const $col = Crayons.@crayon_str $(String(col))
    end)
end
local red, green, blue, cyan, yellow, black, bold, italics, reset # (reassure JuliaLS)

"Report value along with its type."
rept(x) = "$(repr(x))  ::$(typeof(x))"

"Write on stderr."
eprint(args...; kwargs...) = print(stderr, args...; kwargs...)
eprintln(args...; kwargs...) = println(stderr, args...; kwargs...)

"Elide elements from vector if too numerous."
function join_elided(vec, args...; max = 5, repr = true, kwargs...)
    vec = if length(vec) > max
        a, b = vec[1:(max-1)], vec[end:end]
        a, b = dot_display.((a, b), repr)
        vcat(a, "...", b)
    else
        dot_display(vec, repr)
    end
    join(vec, args...; kwargs...)
end

"Special-case sparse vectors so it special-displays missing values."
dot_display(vec, use_repr = true) = use_repr ? repr.(vec) : ["$e" for e in vec]
function dot_display(vec::AbstractSparseVector, use_repr = true)
    res = repeat(["·"], length(vec))
    nzi, nzv = findnz(vec)
    res[nzi] = use_repr ? repr.(nzv) : map(e -> "$e", nzv)
    res
end

"Extract (almost-)faithful console display representation."
wide_repr(io, x) = show(IOContext(io, :limit => true, :compact => true), "text/plain", x)
function wide_repr(x)
    io = IOBuffer()
    wide_repr(io, x)
    String(take!(io))
end

"""
Carefully render arbitrary user input within error messages,
so that it only takes short space if possible,
or else it is mime-displayed at the bottom,
the 'bottom' being defined by anything we would like to render in-'between'.
"""
function render_input(
    io,
    input,
    if_short::Function = (short, type) -> "Received: $short ::$type",
    if_long::Function = (long, type) -> begin
        print(io, "Received: ")
        long()
        print(io, "Type: $type")
    end,
    between::Function = () -> nothing,
)
    T = typeof(input)
    type = sprint(show, T)
    short = repr(input)
    if length(short) + length(type) < 80 && !('\n' in short)
        print(io, if_short("$cyan$short$reset", type))
        between()
    else
        between()
        if_long(() -> wide_repr(io, input), type)
    end
end

end
