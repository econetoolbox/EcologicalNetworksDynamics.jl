module EcologicalNetworksDynamics

using Crayons
using MacroTools
using OrderedCollections
using SparseArrays
using LinearAlgebra

const Option{T} = Union{T,Nothing}

# Common display utils.
include("./display.jl")
using .Display

# ==========================================================================================
# Ecological model internals.

# Data: parsimonious model memory representation.
include("Networks/Networks.jl")
using .Networks

# Code: efficient model simulation.
include("Differentials/Differentials.jl")
using .Differentials

# Interface: ergonomic model manipulation.
include("./Framework/Framework.jl")

# ==========================================================================================
# Exposed interface.

# Factorize out common optional argument processing.
include("./kwargs_helpers.jl")
using .KwargsHelpers

include("./AliasingDicts/AliasingDicts.jl")
using .AliasingDicts

# Factorize out common user input data preprocessing.
include("./GraphDataInputs/GraphDataInputs.jl")
using .GraphDataInputs

include("./multiplex_api.jl")
using .MultiplexApi

const I = Iterators
include("./dedicate_framework_to_model.jl")

# Encapsulated views into internal arrays or pseudo-arrays.
include("./Views/Views.jl")
export extract
using .Views

# Convenience macro to wire this all together.
#  include("./expose_data.jl") # XXX: on hold.

#-------------------------------------------------------------------------------------------
# The actual user-facing components of the package are defined there,
# connecting them to the internals via the framework.
argerr(mess) = throw(ArgumentError(mess))
include("./components/main.jl")

#=
#-------------------------------------------------------------------------------------------
# Shared API internals.
# Most of these should move to the dedicated components files
# once the internals have been refactored to not depend on them.

# Types to represent the model under a pure topological perspective.
include("./Topologies/Topologies.jl")
using .Topologies
# (will be part of the internals after their refactoring)

#-------------------------------------------------------------------------------------------
# "Outer" parts: develop user-facing stuff here.

# Additional exposed utils built on top of components and methods.
include("./default_model.jl")
include("./nontrophic_layers.jl")
include("./simulate.jl")
include("./topology.jl")
include("./diversity.jl")

=#

# Avoid Revise interruptions when redefining methods and properties.
Framework.REVISING = true

end
