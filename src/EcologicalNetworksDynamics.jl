module EcologicalNetworksDynamics

using Crayons
using MacroTools
using OrderedCollections
using SparseArrays

# Common throughout the code.
const EN = EcologicalNetworksDynamics
const I = Iterators
const Option{T} = Union{T,Nothing}
const SparseMatrix{T} = SparseMatrixCSC{T,Int}

# TODO: drop all internal 'export' statements and harmonize all namespacing shenanigans.

#-------------------------------------------------------------------------------------------
# Common utils.

include("./display.jl")
include("./errors.jl")
include("./codegen.jl")

#-------------------------------------------------------------------------------------------
# XXX: whenever ready, big rename:
#   (Networks, N) -> (Data, D) 💥
#   (Framework, F) -> (Systems, S)
#   (NetworkFramework, NF) -> (FrontEnd, F) 💥
#   (Dispatcher, D) -> (DataKind, K)
# ->(Simulation/Code) -> (BackEnd, B)

# Data: parsimonious model memory representation.
include("Networks/Networks.jl")
const N = Networks
using .N: Network

#  # Code: efficient model simulation.
#  include("Differentials/Differentials.jl")
#  using .Differentials # XXX: move after components definitions so they may rely on dispatchers?

#  # Interface: ergonomic model manipulation.
include("./Framework/Framework.jl")
const F = Framework

#  # Additional utils to construct components interface.
#  include("./kwargs_helpers.jl")

#  include("./AliasingDicts/AliasingDicts.jl")
#  const AD = AliasingDicts

#  include("./multiplex_api.jl")
#  using .MultiplexApi

#  # Bring this all together into a library for component authors.
#  include("./NetworkFramework/NetworkFramework.jl")
#  const NF = NetworkFramework
#  using .NF:
    #  D, V, Views, Model, Blueprint, Component, @alias, Map, Adjacency, BinMap, BinAdjacency
#  using .V: extract
#  export Model, extract

#  # The actual user-facing components of the package are defined there,
#  # connecting them to the internals via the framework.
#  include("./components/main.jl")

#=
#-------------------------------------------------------------------------------------------
# Shared API internals.
# Most of these should move to the dedicated components files
# once the internals have been refactored to not depend on them.

# Types to represent the model under a pure topological perspective.
include("./Topologies/Topologies.jl") # XXX: integrate to the internals now.
using .Topologies

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
#  Framework.REVISING = true # XXX: still required?

include("Tests/Tests.jl")

end
