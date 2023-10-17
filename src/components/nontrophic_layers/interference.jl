# Copied and adapted from competition layer.
# Interference differs from other layers because it does not accept a functional form.

module Interference
include("./nti_modules.jl")

# Interference layer builds upon internal potential interference links,
# directly calculated from the raw foodweb.

@propspace interference
@propspace interference.links
@propspace interference.potential_links

@expose_data edges begin
    property(interference.potential_links.matrix)
    depends(Foodweb)
    get(PotentialInterferenceTopology{Bool}, sparse, "potential interference link")
    @species_index
    ref_cached(raw -> Internals.A_interference_full(raw._foodweb) .> 0)
end

@expose_data graph begin
    property(interference.potential_links.number)
    depends(Foodweb)
    ref_cached(raw -> sum(@ref raw.interference.potential_links.matrix))
    get(raw -> @ref raw.interference.potential_links.number)
end

const default = (; intensity = multiplex_defaults[:I][:interference])

include("./interference/topology.jl")
include("./interference/intensity.jl")

# ==========================================================================================
# The layer component brings this all together.

#-------------------------------------------------------------------------------------------
# Aggregated blueprint.

mutable struct Pack <: Blueprint
    topology::Brought(Topology) # This field can't be implied-constructed: forbid 'imply'.
    intensity::Brought(Intensity)
    # For direct use by human caller.
    Pack(; kwargs...) =
        new(fields_from_kwargs(Pack, MultiplexParametersDict(kwargs...); default)...)
    # For use by higher-level nontrophic layers utils.
    Pack(d::MultiplexParametersDict) = new(fields_from_multiplex_parms(:interference, d)...)
end
F.implied_blueprint_for(::Pack, ::_Topology) = F.cannot_imply_construct()
F.implied_blueprint_for(::Pack, ::_Intensity) = Intensity.Flat(default.intensity)
@blueprint Pack "bundled layer components"

function F.expand!(raw, ::Pack)
    # Draw all required data from the scratch
    # to construct Internals layer.
    s = raw._scratch
    layer = Internals.Layer(s[:interference_links], s[:interference_intensity], nothing)
    set_layer!(raw, :interference, layer)
end

#-------------------------------------------------------------------------------------------
# Component.

(false) && (local Layer, _Layer) # (reassure JuliaLS)
# For some (legacy?) reason, the foodweb topology is not the only requirement.
@component begin
    Layer <: Nti.Layer
    requires(BodyMass, MetabolicClass, Topology, Intensity)
    blueprints(Pack::Pack)
end
export Layer

# Calling the component is like calling the (single) corresponding blueprint constructor.
(::_Layer)(args...; kwargs...) = Pack(args...; kwargs...)

end
