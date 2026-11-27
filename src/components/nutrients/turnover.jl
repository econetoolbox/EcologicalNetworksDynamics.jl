module TurnoverDef

using EcologicalNetworksDynamics: Nutrients
using EcologicalNetworksDynamics.Interface: SL, IT

const s, S = SL.NodeField(:nutrients, :turnover)
SL.name_variants(::S) = (:turnover, :turnovers, :Turnover, :Turnovers, :t)
SL.type(::S) = Float64
IT.early_check(::S, t::Real) = IT.non_negative(Float64, t)

const Turnover, _Turnover = IT.define_node_field_component(Nutrients, s)

end
local Turnover, _Turnover # (reassure JuliaLS)
