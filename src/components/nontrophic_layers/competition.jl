abstract type CompetitionTopology <: ModelBlueprint end

# Competition layer builds upon internal potential competition links,
# directly calculated from the raw foodweb.
@expose_data edges begin
    property(potential_competition_links)
    get(PotentialCompetitionTopology{Bool}, sparse, "potential competition link")
    ref_cache(m -> Internals.A_competition_full(m._foodweb) .> 0)
    @species_index
    depends(Foodweb)
end

@expose_data graph begin
    property(n_potential_competition_links)
    ref_cache(m -> sum(m._potential_competition_links))
    get(m -> m._n_potential_competition_links)
    depends(Foodweb)
end

# ==========================================================================================
# Layer topology.

function CompetitionTopology(A = nothing; kwargs...)
    (isnothing(A) && isempty(kwargs)) &&
        argerr("No input given to specify competition links.")

    @kwargs_helpers kwargs

    (!isnothing(A) && given(:A)) && argerr("Redundant competition topology input.\n\
                                            Received both: $A\n\
                                            And          : $(take!(:A)).")

    if !isnothing(A) || given(:A)
        A = given(:A) ? take!(:A) : A
        no_unused_arguments()
        CompetitionTopologyFromRawEdges(A)
    else
        RandomCompetitionTopology(; kwargs...)
    end

end
export CompetitionTopology

mutable struct CompetitionTopologyFromRawEdges <: CompetitionTopology
    A::@GraphData {SparseMatrix, Adjacency}{:bin}
    CompetitionTopologyFromRawEdges(A) = new(@tographdata A EA{:bin})
end

function F.check(model, bp::CompetitionTopologyFromRawEdges)
    P = model._potential_competition_links
    ind = model._species_index
    (; A) = bp
    @check_template_if_sparse A P "potential competition link"
    @check_refs_if_list A "potential competition link" ind template(P)
end

function F.expand!(model, bp::CompetitionTopologyFromRawEdges)
    ind = model._species_index
    (; A) = bp
    @to_sparse_matrix_if_adjacency A ind ind
    expand_topology!(model, :competition, A)
end

@component CompetitionTopologyFromRawEdges requires(Foodweb)
export CompetitionTopologyFromRawEdges

#-------------------------------------------------------------------------------------------
mutable struct RandomCompetitionTopology <: CompetitionTopology
    L::Option{Int64}
    C::Option{Float64}
    symmetry::Bool
    RandomCompetitionTopology(args...) = new(args...)
    function RandomCompetitionTopology(; kwargs...)
        L, C, symmetry = parse_random_links_arguments(:competition, kwargs)
        new(L, C, symmetry)
    end
end

function F.check(model, bp::RandomCompetitionTopology)
    common_random_nti_check(bp)

    np = model.n_producers
    maxL = model.n_potential_competition_links
    (; L) = bp

    if !isnothing(L)
        s(n) = n > 1 ? "s" : ""
        L > maxL && checkfails("Cannot draw L = $L competition link$(s(L)) \
                                with only $np producer$(s(np)) (max: L = $maxL).")
    end
end

function F.expand!(model, bp::RandomCompetitionTopology)
    A = random_links(model, bp, Internals.potential_competition_links)
    expand_topology!(model, :competition, A)
end

@component RandomCompetitionTopology requires(Foodweb)
export RandomCompetitionTopology

#-------------------------------------------------------------------------------------------
@conflicts(CompetitionTopologyFromRawEdges, RandomCompetitionTopology)
# Temporary semantic fix before framework refactoring.
F.componentof(::Type{<:CompetitionTopology}) = CompetitionTopology

#-------------------------------------------------------------------------------------------
@expose_data edges begin
    property(competition_links)
    get(CompetitionLinks{Bool}, sparse, "competition link")
    ref(m -> m._scratch[:competition_links])
    @species_index
    depends(CompetitionTopology)
end

@expose_data graph begin
    property(n_competition_links)
    ref_cache(m -> sum(m._competition_links))
    get(m -> m._n_competition_links)
    depends(CompetitionTopology)
end

#-------------------------------------------------------------------------------------------
display_short(bp::CompetitionTopology; kwargs...) =
    display_short(bp, CompetitionTopology; kwargs...)
display_long(bp::CompetitionTopology; kwargs...) =
    display_long(bp, CompetitionTopology; kwargs...)
function F.display(model, ::Type{<:CompetitionTopology})
    n = model.n_competition_links
    "Competition topology: $n link$(n > 1 ? "s" : "")"
end

# ==========================================================================================
# Layer intensity (constant for now due to limitations of the Internals).

mutable struct CompetitionIntensity <: ModelBlueprint
    gamma::Float64
end
F.expand!(model, bp::CompetitionIntensity) =
    model._scratch[:competition_intensity] = bp.gamma
@component CompetitionIntensity
export CompetitionIntensity

@expose_data graph begin
    property(competition_layer_intensity)
    get(m -> m._scratch[:competition_intensity])
    set!(
        (m, rhs::Float64) -> set_layer_scalar_data!(
            m,
            :competition,
            :competition_intensity,
            :intensity,
            rhs,
        ),
    )
    depends(CompetitionIntensity)
end
function F.display(model, ::Type{<:CompetitionIntensity})
    "Competition intensity: $(model.competition_layer_intensity)"
end

# ==========================================================================================
# Layer functional form.

mutable struct CompetitionFunctionalForm <: ModelBlueprint
    fn::Function
end

function F.check(_, bp::CompetitionFunctionalForm)
    check_functional_form(bp.fn, :competition, checkfails)
end

F.expand!(model, bp::CompetitionFunctionalForm) =
    model._scratch[:competition_functional_form] = bp.fn

@component CompetitionFunctionalForm
export CompetitionFunctionalForm

# TODO: how to encapsulate in a way that user can't add methods to it?
#       Fortunately, overriding the required signature yields a warning. But still.
@expose_data graph begin
    property(competition_layer_functional_form)
    get(m -> m._scratch[:competition_functional_form])
    set!(
        (m, rhs::Function) -> begin
            check_functional_form(rhs, :competition, argerr)
            set_layer_scalar_data!(m, :competition, :competition_functional_form, :f, rhs)
        end,
    )
    depends(CompetitionFunctionalForm)
end

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
