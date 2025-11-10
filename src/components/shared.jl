# Generate typical method to check input atomic values, either for nodes or edges.
function check_value(check, value, ref, name, message)
    check(value) && return value
    index = if isnothing(ref)
        ""
    else
        "[$(join(repr.(ref), ", "))]"
    end
    checkfails("$message: $name$index = $value.")
end

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
