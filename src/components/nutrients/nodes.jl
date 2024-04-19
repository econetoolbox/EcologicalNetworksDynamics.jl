# Nutrients nodes compartments, akin to `Nodes`.
# Two possible blueprints because their number can be inferred from producer species.

# ==========================================================================================
# Call it 'Nodes' because the module is already named 'Nutrients'.
abstract type Nodes <: ModelBlueprint end
# Don't export, to encourage disambiguated access as `Nutrients.Nodes`.

Nodes(raw) =
    if raw isa Symbol
        NodesFromFoodweb(raw)
    else
        RawNodes(raw)
    end

# Akin to Species.
mutable struct RawNodes <: Nodes
    names::Vector{Symbol}
    RawNodes(names) = new(Symbol.(names))
    RawNodes(n::Integer) = new([Symbol(:n, i) for i in 1:n])
    RawNodes(names::Vector{Symbol}) = new(names)
end

function F.check(_, bp::RawNodes)
    (; names) = bp
    # Forbid duplicates (triangular check).
    for (i, a) in enumerate(names)
        for j in (i+1):length(names)
            b = names[j]
            a == b && checkfails("Nutrients $i and $j are both named $(repr(a)).")
        end
    end
end

function add_nutrients!(m, names)
    # Store in the scratch, and only alias to model.producer_growth
    # if the corresponding component is loaded.
    m._scratch[:nutrients_names] = names
    m._scratch[:nutrients_index] = OrderedDict(n => i for (i, n) in enumerate(names))

    # Update topology.
    top = m._topology
    add_nodes!(top, names, :nutrients)

    # For now, consider that the only presence of nutrients
    # implies that every producer species is topologically connected to every nutrient.
    # TODO: maybe this should be alleviated in case feeding coefficients are zero.
    # In this situation, the edges would only appear when adding
    # concentration/half-saturation coefficients.

    # TODO: This is only possible if a foodweb already exists,
    # which leads us to a feature gap in the framework:
    # things need to happen only when special components combinations occur,
    # so as not to require that `Model() + Foodweb() + Nutrients()`
    #  behaves differently than `Model() + Nutrients() + Foodweb()`.
    # Whatever the order here, the following should only happen on the second '+'.
    # For now, work around this by having:
    #  - `Foodweb` expansion check for `Nutrients.Node` presence.
    #  - `Nutrients.Node` expansion check for `Foodweb` presence.
    # But this will not scale.
    Topologies.has_edge_type(top, :trophic) && connect_producers_to_nutrients(m)
    #             ^^^^^
    # + TODO: the above should be something like `has_component(m, Foodweb)` instead.
end

# Either called when adding Nutrients.Nodes to a model with a Foodweb, or the opposite.
function connect_producers_to_nutrients(m)
    edges = repeat(m._producers_mask, 1, m.n_nutrients)
    add_edges_accross_node_types!(m._topology, :species, :nutrients, :trophic, edges)
end

F.expand!(model, bp::Nodes) = add_nutrients!(model, bp.names)

@component RawNodes

#-------------------------------------------------------------------------------------------
mutable struct NodesFromFoodweb <: Nodes
    method::Symbol
    function NodesFromFoodweb(method)
        method = Symbol(method)
        @check_symbol method (:one_per_producer,)
        new(method)
    end
end

function F.early_check(_, bp::NodesFromFoodweb)
    (; method) = bp
    @check_symbol method (:one_per_producer,)
end

function F.expand!(model, bp::NodesFromFoodweb)
    (; method) = bp
    (; n_producers) = model
    names = @build_from_symbol(
        method,
        :one_per_producer => [Symbol(:n, i) for i in 1:n_producers],
    )
    add_nutrients!(model, names)
end

@component NodesFromFoodweb requires(Foodweb)

#-------------------------------------------------------------------------------------------
@conflicts(RawNodes, NodesFromFoodweb)
# Temporary semantic fix before framework refactoring.
F.componentof(::Type{<:Nodes}) = Nodes

# ==========================================================================================
# See similar methods in Species component.

@expose_data graph begin
    property(nutrients_richness, n_nutrients)
    get(m -> length(m._scratch[:nutrients_names]))
    depends(Nutrients.Nodes)
end

@expose_data nodes begin
    property(nutrients_names)
    get(NutrientsNames{Symbol}, "nutrient")
    ref(m -> m._scratch[:nutrients_names])
    depends(Nutrients.Nodes)
end

@expose_data graph begin
    property(nutrients_index)
    ref_cache(m -> m._scratch[:nutrients_index])
    get(m -> deepcopy(m._nutrients_index))
    depends(Nutrients.Nodes)
end

@expose_data graph begin
    property(nutrient_label)
    ref_cache(
        m ->
            (i) -> begin
                names = m._nutrients_names
                n = length(names)
                if 1 <= i <= length(names)
                    names[i]
                else
                    (are, s) = n > 1 ? ("are", "s") : ("is", "")
                    argerr("Invalid index ($(i)) when there $are $n nutrient$s name$s.")
                end
            end,
    )
    get(m -> m._nutrient_label)
    depends(Nutrients.Nodes)
end

# ==========================================================================================
macro nutrients_index()
    esc(:(index(m -> m._nutrients_index)))
end

# ==========================================================================================
display_short(bp::Nodes; kwargs...) = display_short(bp, Nodes; kwargs...)
display_long(bp::Nodes; kwargs...) = display_long(bp, Nodes; kwargs...)
function F.display(model, ::Type{<:Nodes})
    N = model.n_nutrients
    names = model.nutrients_names
    "Nutrients: $N ($(join_elided(names, ", ")))"
end
