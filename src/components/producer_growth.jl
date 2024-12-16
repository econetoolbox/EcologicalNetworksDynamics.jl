# Subtypes commit to specifying the code
# associated with producer growth terms,
# and all required associated data.
# They are all mutually exclusive.
abstract type ProducerGrowth <: Component end
export ProducerGrowth

# For the sake of simplicity, to not have defaults lying everywhere.
# But this is open to discussion.
abstract type ProducerGrowthBlueprint <: Blueprint end
F.implied_blueprint_for(::ProducerGrowthBlueprint, ::Component) = F.cannot_imply_construct()

#-------------------------------------------------------------------------------------------
# Simple logistic growth.

# Only 1 blueprint for now: same name as component, suffixed with '_'.
mutable struct LogisticGrowth_ <: ProducerGrowthBlueprint
    r::Brought(GrowthRate)
    K::Brought(CarryingCapacity)
    producers_competition::Brought(ProducersCompetition)
    LogisticGrowth_(; kwargs...) = new(
        fields_from_kwargs(
            LogisticGrowth_,
            kwargs;
            default = (r = :Miele2019, K = 1, producers_competition = (; diag = 1)),
        )...,
    )
end
@blueprint LogisticGrowth_

function F.expand!(raw, ::LogisticGrowth_)
    # Gather all data set up by brought components
    # to construct the actual functional response value.
    s = raw._scratch
    lg = Internals.LogisticGrowth(
        # Alias so values gets updated on component `write!`.
        s[:producers_competition],
        s[:carrying_capacity],
        # Growth rates are already stored in `model.biorates` at this point.
    )
    raw.producer_growth = lg
end

(false) && (local LogisticGrowth, _LogisticGrowth) # (reassure JuliaLS)
@component begin
    LogisticGrowth <: ProducerGrowth
    requires(GrowthRate, CarryingCapacity, ProducersCompetition)
    blueprints(Blueprint::LogisticGrowth_)
end
export LogisticGrowth

(::_LogisticGrowth)(args...; kwargs...) = LogisticGrowth_(args...; kwargs...)

#-------------------------------------------------------------------------------------------
# Nutrient intake.

mutable struct NutrientIntake_ <: ProducerGrowthBlueprint
    r::Brought(GrowthRate)
    nodes::Brought(Nutrients.Nodes)
    turnover::Brought(Nutrients.Turnover)
    supply::Brought(Nutrients.Supply)
    concentration::Brought(Nutrients.Concentration)
    half_saturation::Brought(Nutrients.HalfSaturation)
    # Convenience elision of e.g. 'nodes = 2': just use NutrientIntake(2) to bring nodes.
    # Alternately, the number of nodes can be inferred
    # from the non-scalar values if any is given.
    function NutrientIntake_(nodes = missing; kwargs...)
        (nodes, default_nodes) = if haskey(kwargs, :nodes)
            ismissing(nodes) ||
                argerr("Nodes specified once as plain argument ($(repr(nodes))) \
                        and once as keyword argument (nodes = $(kwargs[:nodes])).")
            (kwargs[:nodes], false)
        elseif ismissing(nodes)
            ((), true) # <- Default Nutrients.Nodes blueprint constructor.
        else
            (nodes, false)
        end
        fields = fields_from_kwargs(
            NutrientIntake_,
            kwargs;
            # Values from Brose2008.
            default = (;
                r = :Miele2019,
                nodes,
                turnover = 0.25,
                supply = 4,
                concentration = 0.5,
                half_saturation = 0.15,
            ),
        )
        # Careful not to default-bring a blueprint for nodes
        # that would otherwise be inconsistent with user-brought ones.
        if default_nodes
            i_nodes = findfirst(==(:nodes), fieldnames(NutrientIntake_))
            for brought in fields[i_nodes+1:end]
                if F.implies_blueprint_for(brought, Nutrients.Nodes)
                    fields[i_nodes] = nothing # In this case, bring nothing instead.
                    break
                end
            end
        end
        # This blueprint has several different ways of implying nutrient nodes.
        # Check that they are consistent upfront.
        new(fields...)
    end
end
@blueprint NutrientIntake_

function F.expand!(raw, ::NutrientIntake_)
    s = raw._scratch
    ni = Internals.NutrientIntake(
        s[:nutrients_turnover],
        s[:nutrients_supply],
        s[:nutrients_concentration],
        s[:nutrients_half_saturation],
        s[:nutrients_names],
        s[:nutrients_index],
    )
    raw.producer_growth = ni
end

(false) && (local NutrientIntake, _NutrientIntake) # (reassure JuliaLS)
@component begin
    NutrientIntake <: ProducerGrowth
    requires(
        GrowthRate,
        Nutrients.Turnover,
        Nutrients.Supply,
        Nutrients.Concentration,
        Nutrients.HalfSaturation,
    )
    blueprints(Blueprint::NutrientIntake_)
end
export NutrientIntake

(::_NutrientIntake)(args...; kwargs...) = NutrientIntake_(args...; kwargs...)

@conflicts(NutrientIntake, Nti.Layer)

#-------------------------------------------------------------------------------------------
# These are exclusive ways to specify producer growth.
@conflicts(LogisticGrowth, NutrientIntake)
