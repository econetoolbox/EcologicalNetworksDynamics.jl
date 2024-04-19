# Copied and adapted from competition layer.
abstract type FacilitationTopology <: ModelBlueprint end

# Facilitation layer builds upon internal potential facilitation links,
# directly calculated from the raw foodweb.
@expose_data edges begin
    property(potential_facilitation_links)
    get(PotentialFacilitationTopology{Bool}, sparse, "potential facilitation link")
    ref_cache(m -> Internals.A_facilitation_full(m._foodweb) .> 0)
    @species_index
    depends(Foodweb)
end

@expose_data graph begin
    property(n_potential_facilitation_links)
    ref_cache(m -> sum(m._potential_facilitation_links))
    get(m -> m._n_potential_facilitation_links)
    depends(Foodweb)
end

# ==========================================================================================
# Layer topology.

function FacilitationTopology(A = nothing; kwargs...)
    (isnothing(A) && isempty(kwargs)) &&
        argerr("No input given to specify facilitation links.")

    @kwargs_helpers kwargs

    (!isnothing(A) && given(:A)) && argerr("Redundant facilitation topology input.\n\
                                            Received both: $A\n\
                                            And          : $(take!(:A)).")

    if !isnothing(A) || given(:A)
        A = given(:A) ? take!(:A) : A
        no_unused_arguments()
        FacilitationTopologyFromRawEdges(A)
    else
        RandomFacilitationTopology(; kwargs...)
    end

end
export FacilitationTopology

mutable struct FacilitationTopologyFromRawEdges <: FacilitationTopology
    A::@GraphData {SparseMatrix, Adjacency}{:bin}
    FacilitationTopologyFromRawEdges(A) = new(@tographdata A EA{:bin})
end

function F.check(model, bp::FacilitationTopologyFromRawEdges)
    P = model._potential_facilitation_links
    ind = model._species_index
    (; A) = bp
    @check_template_if_sparse A P "potential facilitation link"
    @check_refs_if_list A "potential facilitation link" ind template(P)
end

function F.expand!(model, bp::FacilitationTopologyFromRawEdges)
    ind = model._species_index
    (; A) = bp
    @to_sparse_matrix_if_adjacency A ind ind
    expand_topology!(model, :facilitation, A)
end

@component FacilitationTopologyFromRawEdges requires(Foodweb)
export FacilitationTopologyFromRawEdges

#-------------------------------------------------------------------------------------------
mutable struct RandomFacilitationTopology <: FacilitationTopology
    L::Option{Int64}
    C::Option{Float64}
    symmetry::Bool
    RandomFacilitationTopology(args...) = new(args...)
    function RandomFacilitationTopology(; kwargs...)
        L, C, symmetry = parse_random_links_arguments(:facilitation, kwargs)
        new(L, C, symmetry)
    end
end

function F.check(model, bp::RandomFacilitationTopology)
    common_random_nti_check(bp)

    np = model.n_producers
    nc = model.n_consumers
    maxL = model.n_potential_facilitation_links
    (; L) = bp

    if !isnothing(L)
        s(n) = n > 1 ? "s" : ""
        L > maxL && checkfails("Cannot draw L = $L facilitation link$(s(L)) \
                                with these $np producer$(s(np)) \
                                and $nc consumer$(s(nc)) (max: L = $maxL).")
    end
end

function F.expand!(model, bp::RandomFacilitationTopology)
    A = random_links(model, bp, Internals.potential_facilitation_links)
    expand_topology!(model, :facilitation, A)
end

@component RandomFacilitationTopology requires(Foodweb)
export RandomFacilitationTopology

#-------------------------------------------------------------------------------------------
@conflicts(FacilitationTopologyFromRawEdges, RandomFacilitationTopology)
# Temporary semantic fix before framework refactoring.
F.componentof(::Type{<:FacilitationTopology}) = FacilitationTopology

#-------------------------------------------------------------------------------------------
@expose_data edges begin
    property(facilitation_links)
    get(FacilitationLinks{Bool}, sparse, "facilitation link")
    ref(m -> m._scratch[:facilitation_links])
    @species_index
    depends(FacilitationTopology)
end

@expose_data graph begin
    property(n_facilitation_links)
    ref_cache(m -> sum(m._facilitation_links))
    get(m -> m._n_facilitation_links)
    depends(FacilitationTopology)
end

#-------------------------------------------------------------------------------------------
display_short(bp::FacilitationTopology; kwargs...) =
    display_short(bp, FacilitationTopology; kwargs...)
display_long(bp::FacilitationTopology; kwargs...) =
    display_long(bp, FacilitationTopology; kwargs...)
function F.display(model, ::Type{<:FacilitationTopology})
    n = model.n_facilitation_links
    "Facilitation topology: $n link$(n > 1 ? "s" : "")"
end

# ==========================================================================================
# Layer intensity (constant for now due to limitations of the Internals).

mutable struct FacilitationIntensity <: ModelBlueprint
    eta::Float64
end
F.expand!(model, bp::FacilitationIntensity) =
    model._scratch[:facilitation_intensity] = bp.eta
@component FacilitationIntensity
export FacilitationIntensity

@expose_data graph begin
    property(facilitation_layer_intensity)
    get(m -> m._scratch[:facilitation_intensity])
    set!(
        (m, rhs::Float64) -> set_layer_scalar_data!(
            m,
            :facilitation,
            :facilitation_intensity,
            :intensity,
            rhs,
        ),
    )
    depends(FacilitationIntensity)
end
function F.display(model, ::Type{<:FacilitationIntensity})
    "Facilitation intensity: $(model.facilitation_layer_intensity)"
end

# ==========================================================================================
# Layer functional form.

mutable struct FacilitationFunctionalForm <: ModelBlueprint
    fn::Function
end

function F.check(_, bp::FacilitationFunctionalForm)
    check_functional_form(bp.fn, :facilitation, checkfails)
end

F.expand!(model, bp::FacilitationFunctionalForm) =
    model._scratch[:facilitation_functional_form] = bp.fn

@component FacilitationFunctionalForm
export FacilitationFunctionalForm

@expose_data graph begin
    property(facilitation_layer_functional_form)
    get(m -> m._scratch[:facilitation_functional_form])
    set!(
        (m, rhs::Function) -> begin
            check_functional_form(rhs, :facilitation, argerr)
            set_layer_scalar_data!(
                m,
                :facilitation,
                :facilitation_functional_form,
                :f,
                rhs,
            )
        end,
    )
    depends(FacilitationFunctionalForm)
end

# ==========================================================================================
# The layer component brings this all together.
mutable struct FacilitationLayer <: NtiLayer
    topology::Option{FacilitationTopology}
    intensity::Option{FacilitationIntensity}
    functional_form::Option{FacilitationFunctionalForm}
    FacilitationLayer(; kwargs...) = new(
        fields_from_kwargs(
            FacilitationLayer,
            MultiplexParametersDict(kwargs...);
            default = (
                intensity = multiplex_defaults[:I][:facilitation],
                functional_form = multiplex_defaults[:F][:facilitation],
            ),
        )...,
    )
    FacilitationLayer(d::MultiplexParametersDict) =
        new(fields_from_multiplex_parms(:facilitation, d)...)
end

function F.expand!(model, ::FacilitationLayer)
    s = model._scratch
    layer = Internals.Layer(
        s[:facilitation_links],
        s[:facilitation_intensity],
        s[:facilitation_functional_form],
    )
    set_layer!(model, :facilitation, layer)
end

@component FacilitationLayer requires(BodyMass, MetabolicClass)
export FacilitationLayer
