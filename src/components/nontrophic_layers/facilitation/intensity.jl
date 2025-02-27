# Layer intensity (constant for now due to limitations of the Internals).

(false) && (local Intensity, _Intensity) # (reassure JuliaLS)

# ==========================================================================================
# Blueprints.

module Intensity_
include("../../blueprint_modules.jl")
include("../../blueprint_modules_identifiers.jl")
include("../nti_blueprints.jl")

mutable struct Flat <: Blueprint
    eta::Float64
end
@blueprint Flat "uniform intensity value"
export Flat

F.early_check(bp::Flat) = check(bp.eta)
check(eta) = check_value(>=(0), eta, nothing, :eta, "Not a positive value")

F.expand!(raw, bp::Flat) = raw._scratch[:facilitation_intensity] = bp.eta

end

# ==========================================================================================
# Component.

@component Intensity{Internal} blueprints(Intensity_)
export Intensity

(::_Intensity)(eta) = Intensity.Flat(eta)

@expose_data graph begin
    property(facilitation.intensity)
    get(raw -> raw._scratch[:facilitation_intensity])
    set!(
        (raw, rhs::Float64) -> set_layer_scalar_data!(
            raw,
            :facilitation,
            :facilitation_intensity,
            :intensity,
            rhs,
        ),
    )
    depends(Intensity)
end

function F.shortline(io::IO, model::Model, ::_Intensity)
    eta = model.facilitation.intensity
    print(io, "Facilitation intensity: $eta")
end
