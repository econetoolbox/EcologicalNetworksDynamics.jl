# Namespace intermediate constants within the module to avoid cross-component clashes.
module TemperatureDef
using EcologicalNetworksDynamics.NetworkFramework: EN, NF, D

# Specify datakind.
const d, _D = D.GraphField(:temperature)
D.name_variants(::_D) = (:T, :temperature, :Temperature)
D.type(::_D) = Float64
NF.early_check(::_D, T) = NF.non_negative(Float64, T)

# Generate and execute the code to generate blueprints and component.
# Execute this within toplevel module to still expose the component.
const Temperature, _Temperature = NF.define_graph_field(EN, d)

# Append constructor: default value + celcius unit.
(::_Temperature)(; celc = 20) = Temperature.Raw(NF.convert(Float64, celc) + 273.15)

end
local Temperature, _Temperature # (reassure JuliaLS)
export Temperature
