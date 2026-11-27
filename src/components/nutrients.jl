module Nutrients

using EcologicalNetworksDynamics.Interface: IT

# The compartment defining nutrients nodes, akin to `Species`.
include("nutrients/nodes.jl") # "Nodes" because "Nutrients" is already the module name.
include("nutrients/turnover.jl")
include("nutrients/supply.jl")

# HERE: reintroduce the following fields.
# Further node/edges components regarding this compartment.
#  include("nutrients/concentration.jl")
#  include("nutrients/half_saturation.jl")

end
