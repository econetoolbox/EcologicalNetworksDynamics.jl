module ConcentrationDef

using EcologicalNetworksDynamics: Nutrients
using EcologicalNetworksDynamics.Interface: EN, SL, IT, @alias

const s, S = SL.EdgeField(:nutrients_producers, :concentration)
SL.name_variants(::S) = (
    :concentration,
    :concentrations,
    :Concentration,
    :Concentrations,
    :c,
)
SL.type(::S) = Float64
IT.early_check(::S, c::Real) = IT.non_negative(Float64, c)

const Concentration, _Concentration = IT.define_web_field_component(Nutrients, s;
    requires = [EN.Foodweb, Nutrients.Nodes])
@alias nutrients.concentration nutrients_producers.concentration

end
local Concentration, _Concentration # (reassure JuliaLS)
