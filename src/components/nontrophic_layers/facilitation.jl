# Copied and adapted from competition layer.

module Facilitation
include("./nti_modules.jl")

@propspace facilitation
@propspace facilitation.links
@propspace facilitation.potential_links

@expose_data edges begin
    property(facilitation.potential_links.matrix)
    depends(Foodweb)
    get(PotentialFacilitationTopology{Bool}, sparse, "potential facilitation link")
    @species_index
    ref_cached(raw -> Internals.A_facilitation_full(raw._foodweb) .> 0)
end

@expose_data graph begin
    property(facilitation.potential_links.number)
    depends(Foodweb)
    ref_cached(raw -> sum(@ref raw.facilitation.potential_links.matrix))
    get(raw -> @ref raw.facilitation.potential_links.number)
end

const default = (;
    intensity = multiplex_defaults[:I][:facilitation],
    functional_form = multiplex_defaults[:F][:facilitation],
)

include("./facilitation/topology.jl")
include("./facilitation/intensity.jl")
include("./facilitation/functional_form.jl")

# ==========================================================================================
# The layer component brings this all together.

#-------------------------------------------------------------------------------------------
# Aggregated blueprint.

mutable struct Pack <: Blueprint
    topology::Brought(Topology) # This field can't be implied-constructed: forbid 'imply'.
    intensity::Brought(Intensity)
    functional_form::Brought(FunctionalForm)
    # For direct use by human caller.
    Pack(; kwargs...) =
        new(fields_from_kwargs(Pack, MultiplexParametersDict(kwargs...); default)...)
    # For use by higher-level nontrophic layers utils.
    Pack(d::MultiplexParametersDict) = new(fields_from_multiplex_parms(:facilitation, d)...)
end
F.implied_blueprint_for(::Pack, ::_Topology) = F.cannot_imply_construct()
F.implied_blueprint_for(::Pack, ::_Intensity) = Intensity.Flat(default.intensity)
F.implied_blueprint_for(::Pack, ::_FunctionalForm) = FunctionalForm(default.functional_form)
@blueprint Pack "bundled layer components"

function F.expand!(raw, ::Pack)
    # Draw all required data from the scratch
    # to construct Internals layer.
    s = raw._scratch
    layer = Internals.Layer(
        s[:facilitation_links],
        s[:facilitation_intensity],
        s[:facilitation_functional_form],
    )
    set_layer!(raw, :facilitation, layer)
end

#-------------------------------------------------------------------------------------------
# Component.

(false) && (local Layer, _Layer) # (reassure JuliaLS)
# For some (legacy?) reason, the foodweb topology is not the only requirement.
@component begin
    Layer <: Nti.Layer
    requires(BodyMass, MetabolicClass, Topology, FunctionalForm, Intensity)
    blueprints(Pack::Pack)
end
export Layer

# Calling the component is like calling the (single) corresponding blueprint constructor.
(::_Layer)(args...; kwargs...) = Pack(args...; kwargs...)

end
