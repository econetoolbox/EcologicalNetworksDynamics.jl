module Nutrients

using ..EcologicalNetworksDynamics
const EN = EcologicalNetworksDynamics
using .EN.GraphDataInputs
using .EN.Topologies
import .EN:
    Blueprint,
    Foodweb,
    Framework as F,
    Internal,
    Internals,
    Model,
    argerr,
    join_elided,
    showrange,
    @component,
    @expose_data,
    @get,
    @propspace,
    @ref
using OrderedCollections
using SparseArrays

# (reassure JuliaLS)
include("../macros_keywords.jl")
if (false)
    local nutrients
    include("../../Topologies/Topologies.jl")
    include("../../GraphDataInputs/GraphDataInputs.jl")
    using .Topologies
    using .GraphDataInputs
end

# Dedicated property namespace.
@propspace nutrients

# The compartment defining nutrients nodes, akin to `Species`.
include("./nodes.jl")

# Further node/edges components regarding this compartment.
include("./turnover.jl")
include("./supply.jl")
include("./concentration.jl")
include("./half_saturation.jl")

end
