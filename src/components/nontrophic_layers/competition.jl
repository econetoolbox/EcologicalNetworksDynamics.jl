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

include("./competition/topology.jl")
include("./competition/intensity.jl")
include("./competition/functional_form.jl")

# HERE: to the integrated layer now.

end

#|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
#|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
#|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

# ==========================================================================================
# The layer component brings this all together.
mutable struct CompetitionLayer <: NtiLayer
    topology::Option{CompetitionTopology}
    intensity::Option{CompetitionIntensity}
    functional_form::Option{CompetitionFunctionalForm}
    # For direct use by human caller.
    CompetitionLayer(; kwargs...) = new(
        fields_from_kwargs(
            CompetitionLayer,
            MultiplexParametersDict(kwargs...);
            default = (
                intensity = multiplex_defaults[:I][:competition],
                functional_form = multiplex_defaults[:F][:competition],
            ),
        )...,
    )
    # For use by higher-level nontrophic layers utils.
    CompetitionLayer(d::MultiplexParametersDict) =
        new(fields_from_multiplex_parms(:competition, d)...)
end

function F.expand!(model, ::CompetitionLayer)
    # Draw all required components from the scratch
    # to construct Internals layer.
    s = model._scratch
    layer = Internals.Layer(
        s[:competition_links],
        s[:competition_intensity],
        s[:competition_functional_form],
    )
    set_layer!(model, :competition, layer)
end

# For some (legacy?) reason, the foodweb topology is not the only requirement.
@component CompetitionLayer requires(BodyMass, MetabolicClass)
export CompetitionLayer
