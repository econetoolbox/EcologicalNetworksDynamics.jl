# Temperature is a single graph-level scalar
# useful to calculate allometric values for various biorates.

module TemperatureDef
using EcologicalNetworksDynamics: EN, D, NF

# Specify datakind.
const d = D.GraphField(:temperature)
const _D = typeof(d)
D.name_variants(::_D) = (:T, :temperature, :Temperature)
D.type(::_D) = Float64
NF.intrinsic_check(::_D, input) = NF.non_negative(Float64, input)

# Generate typical component and blueprints.
NF.define_graph_scalar(EN, d) # (define in outer module)

end
local Temperature, _Temperature # (reassure JuliaLS)

# Append constructor: default value.
(::_Temperature)() = Temperature.Raw(293.15)
export Temperature
