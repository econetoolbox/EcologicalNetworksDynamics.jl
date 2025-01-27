module Competition
include("./nti_modules.jl")

# Competition layer builds upon internal potential competition links,
# directly calculated from the raw foodweb.

@propspace competition
@propspace competition.links
@propspace competition.potential_links

@expose_data edges begin
    property(competition.potential_links.matrix)
    depends(Foodweb)
    get(PotentialCompetitionTopology{Bool}, sparse, "potential competition link")
    @species_index
    ref_cached(raw -> Internals.A_competition_full(raw._foodweb) .> 0)
end

@expose_data graph begin
    property(competition.potential_links.number)
    depends(Foodweb)
    ref_cached(raw -> sum(@ref raw.competition.potential_links.matrix))
    get(raw -> @ref raw.competition.potential_links.number)
end

const default = (;
    intensity = multiplex_defaults[:I][:competition],
    functional_form = multiplex_defaults[:F][:competition],
)

include("./competition/topology.jl")
include("./competition/intensity.jl")
include("./competition/functional_form.jl")

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
    Pack(d::MultiplexParametersDict) = new(fields_from_multiplex_parms(:competition, d)...)
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
        s[:competition_links],
        s[:competition_intensity],
        s[:competition_functional_form],
    )
    set_layer!(raw, :competition, layer)
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
