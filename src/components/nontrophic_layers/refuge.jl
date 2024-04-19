# Copied and adapted from competition layer.
abstract type RefugeTopology <: ModelBlueprint end

# Refuge layer builds upon internal potential refuge links,
# directly calculated from the raw foodweb.
@expose_data edges begin
    property(potential_refuge_links)
    get(PotentialRefugeTopology{Bool}, sparse, "potential refuge link")
    ref_cache(m -> Internals.A_refuge_full(m._foodweb) .> 0)
    @species_index
    depends(Foodweb)
end

@expose_data graph begin
    property(n_potential_refuge_links)
    ref_cache(m -> sum(m._potential_refuge_links))
    get(m -> m._n_potential_refuge_links)
    depends(Foodweb)
end

# ==========================================================================================
# Layer topology.

function RefugeTopology(A = nothing; kwargs...)
    (isnothing(A) && isempty(kwargs)) && argerr("No input given to specify refuge links.")

    @kwargs_helpers kwargs

    (!isnothing(A) && given(:A)) && argerr("Redundant refuge topology input.\n\
                                            Received both: $A\n\
                                            And          : $(take!(:A)).")

    if !isnothing(A) || given(:A)
        A = given(:A) ? take!(:A) : A
        no_unused_arguments()
        RefugeTopologyFromRawEdges(A)
    else
        RandomRefugeTopology(; kwargs...)
    end

end
export RefugeTopology

mutable struct RefugeTopologyFromRawEdges <: RefugeTopology
    A::@GraphData {SparseMatrix, Adjacency}{:bin}
    RefugeTopologyFromRawEdges(A) = new(@tographdata A EA{:bin})
end

function F.check(model, bp::RefugeTopologyFromRawEdges)
    P = model._potential_refuge_links
    ind = model._species_index
    (; A) = bp
    @check_template_if_sparse A P "potential refuge link"
    @check_refs_if_list A "potential refuge link" ind template(P)
end

function F.expand!(model, bp::RefugeTopologyFromRawEdges)
    ind = model._species_index
    (; A) = bp
    @to_sparse_matrix_if_adjacency A ind ind
    model._scratch[:refuge_links] = A
    expand_topology!(model, :refuge, A)
end

@component RefugeTopologyFromRawEdges requires(Foodweb)
export RefugeTopologyFromRawEdges

#-------------------------------------------------------------------------------------------
mutable struct RandomRefugeTopology <: RefugeTopology
    L::Option{Int64}
    C::Option{Float64}
    symmetry::Bool
    RandomRefugeTopology(args...) = new(args...)
    function RandomRefugeTopology(; kwargs...)
        L, C, symmetry = parse_random_links_arguments(:refuge, kwargs)
        RandomRefugeTopology(L, C, symmetry)
    end
end

function F.check(model, bp::RandomRefugeTopology)
    common_random_nti_check(bp)

    nprod = model.n_producers
    npreys = model.n_preys
    maxL = model.n_potential_refuge_links
    (; L) = bp

    if !isnothing(L)
        s(n) = n > 1 ? "s" : ""
        L > maxL && checkfails("Cannot draw L = $L refuge link$(s(L)) \
                                with these $nprod producer$(s(nprod)) \
                                and $npreys prey$(s(npreys)) (max: L = $maxL).")
    end
end

function F.expand!(model, bp::RandomRefugeTopology)
    A = random_links(model, bp, Internals.potential_refuge_links)
    expand_topology!(model, :refuge, A)
end

@component RandomRefugeTopology requires(Foodweb)
export RandomRefugeTopology

#-------------------------------------------------------------------------------------------
@conflicts(RefugeTopologyFromRawEdges, RandomRefugeTopology)
# Temporary semantic fix before framework refactoring.
F.componentof(::Type{<:RefugeTopology}) = RefugeTopology

#-------------------------------------------------------------------------------------------
@expose_data edges begin
    property(refuge_links)
    get(RefugeLinks{Bool}, sparse, "refuge link")
    ref(m -> m._scratch[:refuge_links])
    @species_index
    depends(RefugeTopology)
end

@expose_data graph begin
    property(n_refuge_links)
    ref_cache(m -> sum(m._refuge_links))
    get(m -> m._n_refuge_links)
    depends(RefugeTopology)
end

#-------------------------------------------------------------------------------------------
display_short(bp::RefugeTopology; kwargs...) = display_short(bp, RefugeTopology; kwargs...)
display_long(bp::RefugeTopology; kwargs...) = display_long(bp, RefugeTopology; kwargs...)
function F.display(model, ::Type{<:RefugeTopology})
    n = model.n_refuge_links
    "Refuge topology: $n link$(n > 1 ? "s" : "")"
end

# ==========================================================================================
# Layer intensity (constant for now due to limitations of the Internals).

mutable struct RefugeIntensity <: ModelBlueprint
    phi::Float64
end
F.expand!(model, bp::RefugeIntensity) = model._scratch[:refuge_intensity] = bp.phi
@component RefugeIntensity
export RefugeIntensity

@expose_data graph begin
    property(refuge_layer_intensity)
    get(m -> m._scratch[:refuge_intensity])
    set!(
        (m, rhs::Float64) ->
            set_layer_scalar_data!(m, :refuge, :refuge_intensity, :intensity, rhs),
    )
    depends(RefugeIntensity)
end
function F.display(model, ::Type{<:RefugeIntensity})
    "Refuge intensity: $(model.refuge_layer_intensity)"
end

# ==========================================================================================
# Layer functional form.

mutable struct RefugeFunctionalForm <: ModelBlueprint
    fn::Function
end

F.check(_, bp::RefugeFunctionalForm) = check_functional_form(bp.fn, :refuge, checkfails)

F.expand!(model, bp::RefugeFunctionalForm) = model._scratch[:refuge_functional_form] = bp.fn

@component RefugeFunctionalForm
export RefugeFunctionalForm

@expose_data graph begin
    property(refuge_layer_functional_form)
    get(m -> m._scratch[:refuge_functional_form])
    set!(
        (m, rhs::Function) -> begin
            check_functional_form(rhs, :refuge, argerr)
            set_layer_scalar_data!(m, :refuge, :refuge_functional_form, :f, rhs)
        end,
    )
    depends(RefugeFunctionalForm)
end

# ==========================================================================================
# The layer component brings this all together.
mutable struct RefugeLayer <: NtiLayer
    topology::Option{RefugeTopology}
    intensity::Option{RefugeIntensity}
    functional_form::Option{RefugeFunctionalForm}
    RefugeLayer(; kwargs...) = new(
        fields_from_kwargs(
            RefugeLayer,
            MultiplexParametersDict(kwargs...);
            default = (
                intensity = multiplex_defaults[:I][:refuge],
                functional_form = multiplex_defaults[:F][:refuge],
            ),
        )...,
    )
    RefugeLayer(d::MultiplexParametersDict) =
        new(fields_from_multiplex_parms(:refuge, d)...)
end

function F.expand!(model, ::RefugeLayer)
    s = model._scratch
    layer =
        Internals.Layer(s[:refuge_links], s[:refuge_intensity], s[:refuge_functional_form])
    set_layer!(model, :refuge, layer)
end

@component RefugeLayer requires(BodyMass, MetabolicClass)
export RefugeLayer
