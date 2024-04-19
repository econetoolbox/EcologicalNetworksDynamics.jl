# Copied and adapted from competition layer.
# Interference differs from other layers because it does not accept a functional form.
abstract type InterferenceTopology <: ModelBlueprint end

# Interference layer builds upon internal potential interference links,
# directly calculated from the raw foodweb.
@expose_data edges begin
    property(potential_interference_links)
    get(PotentialInterferenceTopology{Bool}, sparse, "potential interference link")
    ref_cache(m -> Internals.A_interference_full(m._foodweb) .> 0)
    @species_index
    depends(Foodweb)
end

@expose_data graph begin
    property(n_potential_interference_links)
    ref_cache(m -> sum(m._potential_interference_links))
    get(m -> m._n_potential_interference_links)
    depends(Foodweb)
end

# ==========================================================================================
# Layer topology.

function InterferenceTopology(A = nothing; kwargs...)
    (isnothing(A) && isempty(kwargs)) &&
        argerr("No input given to specify interference links.")

    @kwargs_helpers kwargs

    (!isnothing(A) && given(:A)) && argerr("Redundant interference topology input.\n\
                                            Received both: $A\n\
                                            And          : $(take!(:A)).")

    if !isnothing(A) || given(:A)
        A = given(:A) ? take!(:A) : A
        no_unused_arguments()
        InterferenceTopologyFromRawEdges(A)
    else
        RandomInterferenceTopology(; kwargs...)
    end

end
export InterferenceTopology

mutable struct InterferenceTopologyFromRawEdges <: InterferenceTopology
    A::@GraphData {SparseMatrix, Adjacency}{:bin}
    InterferenceTopologyFromRawEdges(A) = new(@tographdata A EA{:bin})
end

function F.check(model, bp::InterferenceTopologyFromRawEdges)
    P = model._potential_interference_links
    ind = model._species_index
    (; A) = bp
    @check_template_if_sparse A P "potential interference link"
    @check_refs_if_list A "potential interference link" ind template(P)
end

function F.expand!(model, bp::InterferenceTopologyFromRawEdges)
    ind = model._species_index
    (; A) = bp
    @to_sparse_matrix_if_adjacency A ind ind
    expand_topology!(model, :interference, A)
end

@component InterferenceTopologyFromRawEdges requires(Foodweb)
export InterferenceTopologyFromRawEdges

#-------------------------------------------------------------------------------------------
mutable struct RandomInterferenceTopology <: InterferenceTopology
    L::Option{Int64}
    C::Option{Float64}
    symmetry::Bool
    RandomInterferenceTopology(args...) = new(args...)
    function RandomInterferenceTopology(; kwargs...)
        L, C, symmetry = parse_random_links_arguments(:interference, kwargs)
        new(L, C, symmetry)
    end
end

function F.check(model, bp::RandomInterferenceTopology)
    common_random_nti_check(bp)

    nc = model.n_consumers
    np = model.n_preys
    maxL = model.n_potential_interference_links
    (; L) = bp

    if !isnothing(L)
        s(n) = n > 1 ? "s" : ""
        L > maxL && checkfails("Cannot draw L = $L interference link$(s(L)) \
                                with these $nc consumer$(s(nc)) \
                                and $np prey$(s(np)) (max: L = $maxL).")
    end
end

function F.expand!(model, bp::RandomInterferenceTopology)
    A = random_links(model, bp, Internals.potential_interference_links)
    expand_topology!(model, :interference, A)
end

@component RandomInterferenceTopology requires(Foodweb)
export RandomInterferenceTopology

#-------------------------------------------------------------------------------------------
@conflicts(InterferenceTopologyFromRawEdges, RandomInterferenceTopology)
# Temporary semantic fix before framework refactoring.
F.componentof(::Type{<:InterferenceTopology}) = InterferenceTopology

#-------------------------------------------------------------------------------------------
@expose_data edges begin
    property(interference_links)
    get(InterferenceLinks{Bool}, sparse, "interference link")
    ref(m -> m._scratch[:interference_links])
    @species_index
    depends(InterferenceTopology)
end

@expose_data graph begin
    property(n_interference_links)
    ref_cache(m -> sum(m._interference_links))
    get(m -> m._n_interference_links)
    depends(InterferenceTopology)
end

#-------------------------------------------------------------------------------------------
display_short(bp::InterferenceTopology; kwargs...) =
    display_short(bp, InterferenceTopology; kwargs...)
display_long(bp::InterferenceTopology; kwargs...) =
    display_long(bp, InterferenceTopology; kwargs...)
function F.display(model, ::Type{<:InterferenceTopology})
    n = model.n_interference_links
    "Interference topology: $n link$(n > 1 ? "s" : "")"
end

# ==========================================================================================
# Layer intensity (constant for now due to limitations of the Internals).

mutable struct InterferenceIntensity <: ModelBlueprint
    psi::Float64
end
F.expand!(model, bp::InterferenceIntensity) =
    model._scratch[:interference_intensity] = bp.psi
@component InterferenceIntensity
export InterferenceIntensity

@expose_data graph begin
    property(interference_layer_intensity)
    get(m -> m._scratch[:interference_intensity])
    set!(
        (m, rhs::Float64) -> set_layer_scalar_data!(
            m,
            :interference,
            :interference_intensity,
            :intensity,
            rhs,
        ),
    )
    depends(InterferenceIntensity)
end
function F.display(model, ::Type{<:InterferenceIntensity})
    "Interference intensity: $(model.interference_layer_intensity)"
end

# ==========================================================================================
# The layer component brings this all together.
mutable struct InterferenceLayer <: NtiLayer
    topology::Option{InterferenceTopology}
    intensity::Option{InterferenceIntensity}
    InterferenceLayer(; kwargs...) = new(
        fields_from_kwargs(
            InterferenceLayer,
            MultiplexParametersDict(kwargs...);
            default = (intensity = multiplex_defaults[:I][:interference],),
        )...,
    )
    InterferenceLayer(d::MultiplexParametersDict) =
        new(fields_from_multiplex_parms(:interference, d)...)
end

function F.expand!(model, ::InterferenceLayer)
    s = model._scratch
    layer = Internals.Layer(s[:interference_links], s[:interference_intensity], nothing)
    set_layer!(model, :interference, layer)
end

@component InterferenceLayer requires(BodyMass, MetabolicClass)
export InterferenceLayer
