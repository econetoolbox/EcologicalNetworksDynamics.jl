# Temperature is a single graph-level scalar
# useful to calculate allometric values for various biorates.

(false) && (local Temperature, _Temperature) # (reassure JuliaLS)
export Temperature

module TemperatureDef

using EcologicalNetworksDynamics: EN, D, NF

const d = D.GraphField(:temperature)
const DT = typeof(d)

D.name_variants(::DT) = (:T, :temperature, :Temperature)
D.type(::DT) = Float64
NF.check(::DT, input) = NF.non_negative(Float64, input)

# Codegen + exec.
NF.define_graph_scalar(EN, d)
using .EN: Temperature, _Temperature

# Default value.
(::_Temperature)() = Temperature.Raw(293.15)

end
