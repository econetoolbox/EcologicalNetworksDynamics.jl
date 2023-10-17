# Factorize numerous imports useful within the NTI submodules.
# To be `include`d from these modules.

using SparseArrays

using EcologicalNetworksDynamics
const EN = EcologicalNetworksDynamics
using .EN.Framework
using .EN.AliasingDicts
using .EN.GraphDataInputs
using .EN.KwargsHelpers
using .EN.MultiplexApi
import .EN:
    Blueprint,
    BodyMass,
    Brought,
    Foodweb,
    Internal,
    Internals,
    MetabolicClass,
    Model,
    Option,
    SparseMatrix,
    System,
    argerr,
    checkfails,
    fields_from_kwargs,
    @component,
    @get,
    @propspace,
    @ref,
    @species_index
const F = Framework
import .F: @blueprint

import .EN.NontrophicInteractions:
    check_functional_form,
    expand_topology!,
    fields_from_multiplex_parms,
    multiplex_defaults,
    parse_random_links_arguments,
    random_links,
    random_nti_early_check,
    set_layer!,
    set_layer_scalar_data!
const Nti = EN.NontrophicInteractions

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
    local ( competition, facilitation, interference, refuge )
end
