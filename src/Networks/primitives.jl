"""
Add new data to every node in the class.
The given vector will be moved into a protected Entry/Field:
don't keep reference around or leak them to end users.
"""
function add_field!(c::Class, fname::Symbol, v::Vector{T}) where {T}

    # The data needs to be meaningfully copyable for the COW to work.
    hasmethod(deepcopy, (T,)) || argerr("Cannot add non-deepcopy field.")

    (; name, data) = c
    fname in keys(data) && argerr("Class :$name already contains a field :$fname.")

    (nv, nc) = length((v, c))
    nv == nc || argerr("The given vector (size $nv) does not match the class size ($nc).")

    V = Vector{T}
    data[name] = Entry{V}(Field{V}(v))
end
export add_field!
