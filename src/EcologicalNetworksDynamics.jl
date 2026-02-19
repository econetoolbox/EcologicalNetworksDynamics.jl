module EcologicalNetworksDynamics

using Crayons
using MacroTools
using OrderedCollections
using SparseArrays
using LinearAlgebra
using Graphs
using Distributions

# Common throughout the code.
const EN = EcologicalNetworksDynamics
const Option{T} = Union{T,Nothing}
const SparseMatrix{T} = SparseMatrixCSC{T,Int}
argerr(message, throw = Base.throw) = throw(ArgumentError(message))

# Common display utils.
include("./display.jl")
using .Display

# ==========================================================================================
# Ecological model internals.

# Data: parsimonious model memory representation.
include("Networks/Networks.jl")
const N = Networks

# Code: efficient model simulation.
include("Differentials/Differentials.jl")
using .Differentials

# Interface: ergonomic model manipulation.
include("./Framework/Framework.jl")
include("./kwargs_helpers.jl")
include("./AliasingDicts/AliasingDicts.jl")
include("./multiplex_api.jl")
const F = Framework

# Bring this all together into a library for component authors.
include("./NetworkFramework/NetworkFramework.jl")
const NF = NetworkFramework

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

# Convenience macro to wire this all together.
#  include("./expose_data.jl") # XXX: on hold.

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
