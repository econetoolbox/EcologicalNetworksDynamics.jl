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
const I = Iterators
const Option{T} = Union{T,Nothing}
const SparseMatrix{T} = SparseMatrixCSC{T,Int}
argerr(message, throw = Base.throw) = throw(ArgumentError(message))

"""
Construct the name expression required to add a method to the given item.
- Module.A -> :(\$Module.\$(:A))
- fn -> :(::\$(typeof(fn)))
"""
function methname(T::Type)
    n = T.name
    :($(n.module).$(n.name))
end
methname(U::UnionAll) = methname(U.body)
methname(fn::Function) = :(::$(typeof(fn)))

# Common display utils.
include("./display.jl")
using .Display

# Data: parsimonious model memory representation.
include("Networks/Networks.jl")
const N = Networks

# Code: efficient model simulation.
include("Differentials/Differentials.jl")
using .Differentials # XXX: move after components definitions so they may rely on dispatchers?

# Interface: ergonomic model manipulation.
include("./Framework/Framework.jl")
const F = Framework

# Additional utils to construct components interface.
include("./kwargs_helpers.jl")
include("./AliasingDicts/AliasingDicts.jl")
#  include("./multiplex_api.jl")
#  using .KwargsHelpers
#  const AD = AliasingDicts

#  # Bring this all together into a library for component authors.
#  include("./NetworkFramework/NetworkFramework.jl")
#  using .NetworkFramework
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
Framework.REVISING = true

end
