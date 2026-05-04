module TestUser

# XXX: translate or clear previous tests under onhold/ folder.

# Run all .jl files we can find except the current one (and without recursing).
only = [
    "01-node_class.jl",
    "02-edge_web.jl",
    "03-graph_scalar.jl",
    "04-node_field.jl",
    "05-sparse_node_field.jl",
    "99-components.jl",
    "100-kwargs.jl",
] # Unless some files are specified here, in which case only run these.
if isempty(only)
    folder = dirname(@__FILE__)
    for file in readdir(folder)
        path = joinpath(folder, file)
        if !endswith(path, ".jl") || (abspath(path) == @__FILE__)
            continue
        end
        include(path)
    end
else
    for file in only
        include(file)
    end
end

end
