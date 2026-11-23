# Hill exponent is a single graph-level scalar
# useful to calculate allometric values for various biorates.
module HillExponentDef

using EcologicalNetworksDynamics.Interface: EN, IT, SL

const s, S = SL.GraphField(:hill_exponent)
SL.name_variants(::S) = (:h, :hill_exponent, :HillExponent)
SL.type(::S) = Float64
IT.early_check(::S, input) = IT.non_negative(Float64, input)

const HillExponent, _HillExponent = IT.define_graph_field(EN, s)

# Default.
(::_HillExponent)() = HillExponent.Raw(2)

end
local HillExponent, _HillExponent # (reassure JuliaLS)
export HillExponent
