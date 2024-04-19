module NontrophicInteractions

# TODO: how to ease this boilerplate?
using ..EcologicalNetworksDynamics
const EN = EcologicalNetworksDynamics
using .EN.Framework
using .EN.AliasingDicts
using .EN.GraphDataInputs
using .EN.KwargsHelpers
using .EN.MultiplexApi
using .EN.Topologies
import .EN: Option, argerr, Internals, @species_index, ModelBlueprint, fields_from_kwargs
const F = Framework
using SparseArrays

# For every non-trophic layer,
# one 'Topology' component is defined to specify the associated links between species.
#
# There are typically two blueprints for each topology component.:
#   - Specify the raw links.
#   - Draw them at random from a desired number of links XOR connectance
#     and a symmetry requirement.
#     This is a case of *random expansion*, so (model + nti != model + nti) is possible :\
#
# Then, other dependent components specify further data associated with these links:
#   - 'Intensity' (currently limited to uniform intensity by the Internals).
#   - 'FunctionalForm' ('code' component).
# In the future, I expect that more associated data
# can flesh the above, and maybe that they will differ depending on the layer.
#
# Eventuall, one 'Layer' components, considered as bringing 'code'
# glues all the above together into one functional unit,
# and constructs the underlying internal 'Layer'.
#
# NTI layers specifications are maybe the most heavily duplicated code
# within the components specifications.
# But boilerplate should be alleviated
# with refactoring of the internals then the framework,
# and replication is desired here because competition layers
# are expected to diverge in the future.

# The layers defined in this module in look a lot like each other,
# but don't factorize them too much
# as I suspect that they are likely to diverge in the future.
# Still, the following pieces are common today:
include("./nontrophic_components_utils.jl")

# Some non-trophic layer parameters allow default values,
# the others need to be explicitly specified.

# Use named methods instead of lambdas to get better display.
default_competition_functional_form(x, dx) = x < 0 ? x : max(0, x * (1 - dx))
default_facilitation_functional_form(x, dx) = x * (1 + dx)
default_refuge_functional_form(x, dx) = x / (1 + dx)

multiplex_defaults = MultiplexParametersDict(;
    intensity = InteractionDict(;
        competition = 1.0,
        facilitation = 1.0,
        interference = 1.0,
        refuge = 1.0,
    ),
    functional_form = InteractionDict(;
        competition = default_competition_functional_form,
        facilitation = default_facilitation_functional_form,
        refuge = default_refuge_functional_form,
        # (interference has no functional form)
    ),
    symmetry = InteractionDict(;
        competition = true,
        facilitation = false,
        interference = true,
        refuge = false,
    ),
)

abstract type NtiLayer <: ModelBlueprint end
export NtiLayer

include("./competition.jl")
include("./facilitation.jl")
include("./interference.jl")
include("./refuge.jl")

end
