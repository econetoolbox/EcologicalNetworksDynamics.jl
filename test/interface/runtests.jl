module Interface

# XXX: translate or clear previous tests under onhold/ folder.

include("./symbols.jl")

# Input checking.
include("./convert.jl")
include("./lists.jl")

# Typical network compartments.
include("graph_field.jl")
include("class.jl")
include("web.jl")
include("subclass.jl")
include("node_field.jl")
include("allometric_node_field.jl")
include("edge_field.jl")
include("kwargs.jl")

# Components particularities.
include("components.jl")

end
