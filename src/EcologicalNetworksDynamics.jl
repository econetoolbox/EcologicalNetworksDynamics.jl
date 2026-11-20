module EcologicalNetworksDynamics

using Crayons
using MacroTools
using OrderedCollections
using SparseArrays

const EN = EcologicalNetworksDynamics
const I = Iterators

#-------------------------------------------------------------------------------------------
# Common utils.

const Option{T} = Union{T,Nothing}
const SparseMatrix{T} = SparseMatrixCSC{T,Int}

include("./shared.jl")
include("./display.jl")
include("./errors.jl")
include("./codegen.jl")

#-------------------------------------------------------------------------------------------
# XXX: whenever ready, big rename:
#   [x] (Framework, F) -> (ComponentsSystems, CS)
#   [.] (Dispatchers, D) -> (Selectors, SL)
#   [ ] (Networks, N) -> (Data, D) 💥
#   [ ] (NetworkFramework, NF) -> (Frontend, F) 💥
#   [ ] (Simulation/Code) -> (Backend, B)
#
#   => Library: list of components.

# Data: parsimonious model memory representation.
include("Networks/Networks.jl")
const N = Networks

#  # Code: efficient model simulation.
#  include("Differentials/Differentials.jl")
#  using .Differentials # XXX: move after components definitions so they may rely on dispatchers?

#  # Interface: ergonomic model manipulation.
include("./ComponentsSystems/ComponentsSystems.jl")
const CS = ComponentsSystems

# Additional utils to construct components interface.
include("./kwargs_helpers.jl")

include("./AliasingDicts/AliasingDicts.jl")
const AD = AliasingDicts

include("./multiplex_api.jl")

# Bring this all together into a library for component authors.
include("./NetworkFramework/NetworkFramework.jl")
const NF = NetworkFramework

# The actual user-facing components of the package are defined there,
# connecting them to the internals via the framework.
include("./components/main.jl")

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
#  Components.REVISING = true # XXX: still required?

include("Tests/Tests.jl")

# ==========================================================================================
# Default exposed interface (+ components provide their own alongside their definition).

using .MultiplexApi
export interactions_names, multiplex_parameters_names

using .NetworkFramework
export Blueprint, Component, Model, has_component, Allometry
export extract, spextract

# XXX: cleanup "onhold" files that would not have been deleted yet.

end
