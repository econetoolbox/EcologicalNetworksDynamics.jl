# First example of a single network-level scalar.

# Namespace intermediate constants within the module to avoid cross-component clashes.
module TemperatureDef
using EcologicalNetworksDynamics.NetworkFramework: EN, NF, D

# Specify datakind.
const d, _D = D.GraphField(:temperature)
D.name_variants(::_D) = (:T, :temperature, :Temperature)
D.type(::_D) = Float64
NF.intrinsic_check(::_D, T) = NF.non_negative(Float64, T)

# Generate and execute the code to generate blueprints and component.
# Execute this within toplevel module to still expose the component.
NF.define_graph_scalar(EN, d)

end
local Temperature, _Temperature # (reassure JuliaLS)

# Append constructor: default value.
(::_Temperature)() = Temperature.Raw(293.15)
export Temperature
