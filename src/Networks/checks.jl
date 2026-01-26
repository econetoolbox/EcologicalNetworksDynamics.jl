# Input guards.

function check_free_name(n::Network, name::Symbol)
    (; classes, webs) = n
    name in keys(classes) && err("There is already a class named $(repr(name)).")
    name in keys(webs) && err("There is already a web named $(repr(name)).")
end

function check_class_name(n::Network, name::Symbol)
    (; classes) = n
    name in keys(classes) || err("Not a class in the network: $(repr(name)).")
end

function check_web_name(n::Network, name::Symbol)
    (; webs) = n
    name in keys(webs) || err("Not a web in the network: $(repr(name)).")
end

# All network data must be meaningfully copyable for COW to make sense.
function check_value(value)
    T = typeof(value)
    hasmethod(deepcopy, (T,)) || err("Cannot add non-deepcopy field:\n$value ::$T")
end

is_label(label::Symbol, n::Network) =
    read(n.index) do index
        haskey(index.forward, label)
    end

is_label(label::Symbol, index::Index) = haskey(index.forward, label)
is_label(label::Symbol, class::Class) = is_label(label, class.index)

struct LabelError <: Exception
    name::Symbol
    class::Option{Symbol} # None for root.
    valids::Index
end
laberr(l, c, n) = throw(LabelError(l, c, n))

function check_label(label::Symbol, n::Network)
    is_label(label, n) || laberr(label, nothing, read(deepcopy, n.index))
    label
end

function check_label(label::Symbol, index::Index, class::Symbol)
    is_label(label, index) || laberr(label, class, index)
    label
end
check_label(label::Symbol, class::Class) = check_label(label, class.index, class.name)

function Base.showerror(io::IO, e::LabelError)
    (; name, class, valids) = e
    # TODO: display elided valid names or closest match.
    if isnothing(class)
        print(io, "Label does not refer to a node in the network: $(repr(name)).")
    else
        print(io, "Label does not refer to a node in $(repr(class)) class: $(repr(name)).")
    end
    print(io, "\nValid labels: $(collect(keys(valids))).")
end
