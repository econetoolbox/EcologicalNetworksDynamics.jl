# Namespace intermediate constants within the module to avoid cross-component clashes.
module TemperatureDef
using EcologicalNetworksDynamics.Interface: EN, IT, SL

# Specify datakind.
const s, S = SL.GraphField(:temperature)
SL.name_variants(::S) = (:T, :temperature, :Temperature)
SL.type(::S) = Float64
IT.early_check(::S, T) = IT.non_negative(Float64, T)

# Generate and execute the code to generate blueprints and component.
# Execute this within toplevel module to still expose the component.
const Temperature, _Temperature = IT.define_graph_field(EN, s)

# Append constructor: default value + celcius unit.
(::_Temperature)(; celc = 20) = Temperature.Raw(IT.convert(Float64, celc) + 273.15)

end
local Temperature, _Temperature # (reassure JuliaLS)
export Temperature
