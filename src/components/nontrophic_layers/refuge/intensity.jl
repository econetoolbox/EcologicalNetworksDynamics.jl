# Layer intensity (constant for now due to limitations of the Internals).

(false) && (local Intensity, _Intensity) # (reassure JuliaLS)

# ==========================================================================================
# Blueprints.

module Intensity_
include("../../blueprint_modules.jl")
include("../../blueprint_modules_identifiers.jl")
include("../nti_blueprints.jl")

mutable struct Flat <: Blueprint
    phi::Float64
end
@blueprint Flat "uniform intensity value"
export Flat

F.early_check(bp::Flat) = check(bp.phi)
check(phi) = check_value(>=(0), phi, nothing, :phi, "Not a positive value")

F.expand!(raw, bp::Flat) = raw._scratch[:refuge_intensity] = bp.phi

end

# ==========================================================================================
# Component.

@component Intensity{Internal} blueprints(Intensity_)
export Intensity

(::_Intensity)(phi) = Intensity.Flat(phi)

@expose_data graph begin
    property(refuge.intensity)
    get(raw -> raw._scratch[:refuge_intensity])
    set!(
        (raw, rhs::Float64) ->
            set_layer_scalar_data!(raw, :refuge, :refuge_intensity, :intensity, rhs),
    )
    depends(Intensity)
end

function F.shortline(io::IO, model::Model, ::_Intensity)
    phi = model.refuge.intensity
    print(io, "Refuge intensity: $phi")
end
