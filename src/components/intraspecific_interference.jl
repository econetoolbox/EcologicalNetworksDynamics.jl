module IntraspecificInterferenceDef

using EcologicalNetworksDynamics.Interface: EN, SL, IT

const s, S = SL.NodeField(:consumers, :intraspecific_interference)
SL.name_variants(::S) = (
    :intraspecific_interference,
    :intraspecific_interferences,
    :IntraspecificInterference,
    :IntraspecificInterferences,
    :c,
)
SL.type(::S) = Float64
IT.early_check(::S, c::Real) = IT.non_negative(Float64, c)

const IntraspecificInterference, _IntraspecificInterference =
    IT.define_node_field_component(EN, s)

end
local IntraspecificInterference, _IntraspecificInterference # (reassure JuliaLS)
export IntraspecificInterference
