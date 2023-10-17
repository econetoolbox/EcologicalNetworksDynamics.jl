# Layer intensity (constant for now due to limitations of the Internals).

(false) && (local Intensity, _Intensity) # (reassure JuliaLS)

# ==========================================================================================
# Blueprints.

module Intensity_
include("../../blueprint_modules.jl")
include("../../blueprint_modules_identifiers.jl")
include("../nti_blueprints.jl")

mutable struct Flat <: Blueprint
    gamma::Float64
end
@blueprint Flat "uniform intensity value"
export Flat

F.early_check(bp::Flat) = check(bp.gamma)
check(gamma) = check_value(>=(0), gamma, nothing, :gamma, "Not a positive value")

F.expand!(raw, bp::Flat) = raw._scratch[:competition_intensity] = bp.gamma

end

# ==========================================================================================
# Component.

@component Intensity{Internal} blueprints(Intensity_)
export Intensity

(::_Intensity)(gamma) = Intensity.Flat(gamma)

@expose_data graph begin
    property(competition.intensity)
    get(raw -> raw._scratch[:competition_intensity])
    set!(
        (raw, rhs::Float64) -> set_layer_scalar_data!(
            raw,
            :competition,
            :competition_intensity,
            :intensity,
            rhs,
        ),
    )
    depends(Intensity)
end

function F.shortline(io::IO, model::Model, ::_Intensity)
    gamma = model.competition.intensity
    print(io, "Competition intensity: $gamma")
end
