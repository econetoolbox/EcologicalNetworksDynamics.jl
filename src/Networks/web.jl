# HERE: implement.
struct Web end

"""
Fork web, called when COW-pying the whole network.
"""
function fork(w::Web)
    (;) = w
    Web()
end

entries(::Web) = ()
