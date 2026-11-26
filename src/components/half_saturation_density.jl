module HalfSaturationDensityDef

using EcologicalNetworksDynamics.Interface: EN, SL, IT

const s, S = SL.NodeField(:consumers, :half_saturation_density)
SL.name_variants(::S) = (
    :half_saturation_density,
    :half_saturation_densities,
    :HalfSaturationDensity,
    :HalfSaturationDensities,
    :B0,
)
SL.type(::S) = Float64
IT.early_check(::S, B0::Real) = IT.non_negative(Float64, B0)

const HalfSaturationDensity, _HalfSaturationDensity = IT.define_node_field_component(EN, s)

end
local HalfSaturationDensity, _HalfSaturationDensity # (reassure JuliaLS)
export HalfSaturationDensity
