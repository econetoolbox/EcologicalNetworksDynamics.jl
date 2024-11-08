# Factorize numerous imports useful within the NTI submodules.
# To be `include`d from these modules.

using EcologicalNetworksDynamics
const EN = EcologicalNetworksDynamics
using .EN.Framework
using .EN.AliasingDicts
using .EN.GraphDataInputs
using .EN.KwargsHelpers
using .EN.MultiplexApi
using .EN.Topologies
import .EN:
    Blueprint,
    Foodweb,
    Internal,
    Internals,
    Model,
    Option,
    SparseMatrix,
    argerr,
    checkfails,
    fields_from_kwargs,
    @component,
    @get,
    @propspace,
    @ref,
    @species_index
const F = Framework
using SparseArrays

# (reassure JuliaLS)
include("../macros_keywords.jl")
if (false)
    include("../../Topologies/Topologies.jl")
    include("../../GraphDataInputs/GraphDataInputs.jl")
    include("../../kwargs_helpers.jl")
    include("../../multiplex_api.jl")
    using .Topologies
    using .GraphDataInputs
    using .KwargsHelpers
    using .MultiplexApi: MultiplexParametersDict, InteractionDict, interactions_names
    using .AliasingDicts: expand
    local (competition,)
end

