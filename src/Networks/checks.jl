# Input guards.

function check_free_name(n::Network, name::Symbol)
    (; classes, webs) = n
    name in keys(classes) && err("There is already a class named :$name.")
    name in keys(webs) && err("There is already a web named :$name.")
end

function check_class_name(n::Network, name::Symbol)
    (; classes) = n
    name in keys(classes) || err("Not a class in the network: :$name.")
end

function check_web_name(n::Network, name::Symbol)
    (; webs) = n
    name in keys(webs) || err("Not a web in the network: :$name.")
end

# All network data must be meaningfully copyable for COW to make sense.
function check_value(value)
    T = typeof(value)
    hasmethod(deepcopy, (T,)) || err("Cannot add non-deepcopy field:\n$value ::$T")
end
