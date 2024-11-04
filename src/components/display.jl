# Display matrix nonzero values ranges.
function showrange(io::IO, m::SparseMatrix)
    nz = findnz(m)[3]
    if isempty(nz)
        print(io, "·")
    else
        min, max = extrema(nz)
        if min == max
            print(io, "$min")
        else
            print(io, "$min to $max")
        end
    end
end
