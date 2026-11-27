module MaximumConsumptionDef
using EcologicalNetworksDynamics.Interface: EN, SL, IT, Allometry, @alias

const s, S = SL.NodeField(:consumers, :maximum_consumption)
SL.name_variants(::S) = (
    :maximum_consumption,
    :maximum_consumptions,
    :MaximumConsumption,
    :MaximumConsumptions,
    :y,
)
SL.type(::S) = Float64
IT.early_check(::S, d::Real) = IT.non_negative(Float64, d)

# Allometric blueprint.
# TODO: since only consumers are involved,
# does it make sense to receive and process a full allometric dict here?
miele2019() = Allometry(; ectotherm = (a = 4, b = 0), invertebrate = (a = 8, b = 0))
albp = IT.define_allometry_blueprints(EN, s; base = :Miele2019 => miele2019())

const MaximumConsumption, _MaximumConsumption =
    IT.define_node_field_component(EN, s; blueprints = [albp])

@alias y consumers.maximum_consumption

(::_MaximumConsumption)(default::Symbol) = IT.from_name(default,
    :Miele2019 => () -> MaximumConsumption.Allometric(default),
    ; s)

end
local MaximumConsumption, _MaximumConsumption # (reassure JuliaLS)
export MaximumConsumption
