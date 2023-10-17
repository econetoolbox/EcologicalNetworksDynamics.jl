# Display values ranges.
function showrange(io::IO, values)
    min, max = extrema(values)
    if min == max
        print(io, "$min")
    else
        print(io, "$min to $max")
    end
end

# Restrict to nonzero values.
function showrange(io::IO, m::AbstractSparseArray)
    nz = findnz(m)[3]
    if isempty(nz)
        print(io, "·")
    else
        showrange(io, nz)
    end
end
