module Nutrients

# Regarding properties in this module,
# strict namespacing of them is not possible yet,
# so prefix most of them with `nutrients_` in the meantime.

# TODO: how to ease this boilerplate?
using ..EcologicalNetworksDynamics
const EN = EcologicalNetworksDynamics
using .EN.GraphDataInputs
using .EN.Framework
import .EN: Framework as F, Internals, ModelBlueprint, join_elided, @component, @expose_data
using OrderedCollections
using SparseArrays
using .EN.Topologies
argerr = EN.argerr

# The compartment defining nutrients nodes, akin to `Species`.
include("./nodes.jl")

# All other nutrient-related data depend on nutrient 'nodes'
# but blueprints can typically infer/'imply' them,
# just like the foodweb can infer the 'species' compartment.
include("./turnover.jl")
include("./supply.jl")
include("./concentration.jl")
include("./half_saturation.jl")

end
