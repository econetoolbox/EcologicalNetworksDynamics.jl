# Layer intensity (constant for now due to limitations of the Internals).

(false) && (local Intensity, _Intensity) # (reassure JuliaLS)

# ==========================================================================================
# Blueprints.

module Intensity_
include("../../blueprint_modules.jl")
include("../../blueprint_modules_identifiers.jl")
include("../nti_blueprints.jl")

mutable struct Flat <: Blueprint
    psi::Float64
end
@blueprint Flat "uniform intensity value"
export Flat

F.early_check(bp::Flat) = check(bp.psi)
check(psi) = check_value(>=(0), psi, nothing, :psi, "Not a positive value")

F.expand!(raw, bp::Flat) = raw._scratch[:interference_intensity] = bp.psi

end

# ==========================================================================================
# Component.

@component Intensity{Internal} blueprints(Intensity_)
export Intensity

(::_Intensity)(psi) = Intensity.Flat(psi)

@expose_data graph begin
    property(interference.intensity)
    get(raw -> raw._scratch[:interference_intensity])
    set!(
        (raw, rhs::Float64) -> set_layer_scalar_data!(
            raw,
            :interference,
            :interference_intensity,
            :intensity,
            rhs,
        ),
    )
    depends(Intensity)
end

function F.shortline(io::IO, model::Model, ::_Intensity)
    psi = model.interference.intensity
    print(io, "Interference intensity: $psi")
end
