module EcologicalNetworksDynamics

# Common display utils.
include("./display.jl")

include("Networks/Networks.jl")
using .Networks

include("Differentials/Differentials.jl")

#= Silent all this during internals refactoring.

using Crayons
using MacroTools
using OrderedCollections
using SparseArrays
using Graphs

const imap = Iterators.map
const ifilter = Iterators.filter
iid(it) = imap(identity, it) # Useful to not leak refs.

#-------------------------------------------------------------------------------------------
# Shared API internals.
# Most of these should move to the dedicated components files
# once the internals have been refactored to not depend on them.

# Common error to throw on user input error.
argerr(mess, raise = throw) = raise(ArgumentError(mess))

# Alias common types.
const Option{T} = Union{Nothing,T}
const SparseMatrix{T} = SparseMatrixCSC{T,Int64}

# Basic equivalence relation for recursive use.
function equal_fields(a::T, b::T; ignore = Set{Symbol}()) where {T}
    for name in fieldnames(T)
        if name in ignore
            continue
        end
        u, v = getfield.((a, b), name)
        u == v || return false
    end
    true
end

include("./AliasingDicts/AliasingDicts.jl")
using .AliasingDicts

include("./multiplex_api.jl")
using .MultiplexApi

# Types to represent the model under a pure topological perspective.
include("./Topologies/Topologies.jl")
using .Topologies
# (will be part of the internals after their refactoring)

#-------------------------------------------------------------------------------------------
# "Inner" parts: legacy internals.

# The entire implementation has been brutally made private
# so that we can focus on constructing
# an implementation-independent API on top of it, from scratch.
# Once this API is completed, we expect publishing the package,
# the associated article, and then only perform deep refactoring of the "Internals".
include("./Internals/Internals.jl")

# Basic API reconstruction principle:
#   make the package work again,
#   but without re-exporting anything from Internals.
import .Internals
using .Internals: niche_model, cascade_model
export niche_model, cascade_model # Or the least.

#-------------------------------------------------------------------------------------------
# "Abstract" parts: the framework for developing user API.

# The System/Components framework code used for the API is there.
# This module is needed for package component developers.
include("./Framework/Framework.jl")

#-------------------------------------------------------------------------------------------
# "Outer" parts: develop user-facing stuff here.

# Factorize out common optional argument processing.
include("./kwargs_helpers.jl")
using .KwargsHelpers

# Factorize out common user input data preprocessing.
include("./GraphDataInputs/GraphDataInputs.jl")
using .GraphDataInputs

# Encapsulated views into internal arrays or pseudo-arrays.
include("./dedicate_framework_to_model.jl")
include("./graph_views.jl")
using .GraphViews

# Convenience macro to wire this all together.
include("./expose_data.jl")

# The actual user-facing components of the package are defined there,
# connecting them to the internals via the framework.
include("./components/main.jl")

# Additional exposed utils built on top of components and methods.
include("./default_model.jl")
include("./nontrophic_layers.jl")
include("./simulate.jl")
include("./topology.jl")
include("./diversity.jl")

# Avoid Revise interruptions when redefining methods and properties.
Framework.REVISING = true

=#
end
