# Hill exponent is a single graph-level scalar
# useful to calculate allometric values for various biorates.

(false) && (local HillExponent, _HillExponent) # (reassure JuliaLS)
export HillExponent

module HillExponentDef

using EcologicalNetworksDynamics: EN, D, NF

const d = D.GraphField(:hill_exponent)
const DT = typeof(d)

D.name_variants(::DT) = (:h, :hill_exponent, :HillExponent)
D.type(::DT) = Float64
NF.check(::DT, input) = NF.non_negative(Float64, input)

# Codegen + exec.
NF.define_graph_scalar(EN, d)
using .EN: HillExponent, _HillExponent

end
