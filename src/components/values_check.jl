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
