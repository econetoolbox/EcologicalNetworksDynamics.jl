module Display

using SparseArrays

# Elide elements from vector if too numerous.
function join_elided(vec, args...; max = 5, repr = true, kwargs...)
    vec = if length(vec) > max
        a, b = vec[1:max-1], vec[end:end]
        a, b = dot_display.((a, b), repr)
        vcat(a, "...", b)
    else
        dot_display(vec, repr)
    end
    join(vec, args...; kwargs...)
end
export join_elided

# Special-case sparse vectors so it special-displays missing values.
dot_display(vec, use_repr = true) = use_repr ? repr.(vec) : ["$e" for e in vec]
function dot_display(vec::AbstractSparseVector, use_repr = true)
    res = repeat(["·"], length(vec))
    nzi, nzv = findnz(vec)
    res[nzi] = use_repr ? repr.(nzv) : map(e -> "$e", nzv)
    res
end

end
