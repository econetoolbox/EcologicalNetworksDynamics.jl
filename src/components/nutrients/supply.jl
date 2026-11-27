module SupplyDef

using EcologicalNetworksDynamics: Nutrients
using EcologicalNetworksDynamics.Interface: SL, IT

const s, S = SL.NodeField(:nutrients, :supply)
SL.name_variants(::S) = (:supply, :supplies, :Supply, :Supplies, :t)
SL.type(::S) = Float64
IT.early_check(::S, t::Real) = IT.non_negative(Float64, t)

const Supply, _Supply = IT.define_node_field_component(Nutrients, s)

end
local Supply, _Supply # (reassure JuliaLS)
