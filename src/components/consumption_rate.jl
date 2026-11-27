module ConsumptionRateDef

using EcologicalNetworksDynamics.Interface: EN, SL, IT, @alias

const s, S = SL.NodeField(:consumers, :consumption_rate)
SL.name_variants(::S) = (
    :consumption_rate,
    :consumption_rates,
    :ConsumptionRate,
    :ConsumptionRates,
    :alpha,
)
SL.type(::S) = Float64
IT.early_check(::S, alpha::Real) = IT.non_negative(Float64, alpha)

const ConsumptionRate, _ConsumptionRate = IT.define_node_field_component(EN, s)
@alias alpha consumers.consumption_rate

end
local ConsumptionRate, _ConsumptionRate # (reassure JuliaLS)
export ConsumptionRate
