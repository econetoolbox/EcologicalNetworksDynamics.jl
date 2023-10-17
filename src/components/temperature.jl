# Temperature is a single graph-level scalar
# useful to calculate allometric values for various biorates.

# (reassure JuliaLS)
(false) && (local Temperature, _Temperature)

# ==========================================================================================
# Blueprints.

module Temperature_
include("blueprint_modules.jl")

#-------------------------------------------------------------------------------------------
# From raw value.

mutable struct Raw <: Blueprint
    T::Float64 # Kelvin.
end
@blueprint Raw "value (Kelvin)"
export Raw

F.early_check(bp::Raw) = check(bp.T)
check(T) = check_value(>=(0), T, nothing, :T, "Not a positive (Kelvin) value")

F.expand!(raw, bp::Raw) = raw.environment = Internals.Environment(bp.T)

end

# ==========================================================================================
# Component and generic constructors.

@component Temperature{Internal} blueprints(Temperature_)
export Temperature

(::_Temperature)(T = 293.15) = Temperature.Raw(T)

# Basic query.
@expose_data graph begin
    property(temperature, T)
    depends(Temperature)
    get(raw -> raw.environment.T)
    set!((raw, rhs::Real) -> begin
        Temperature_.check(rhs)
        raw.environment.T = rhs
    end)
end

# Display.
F.shortline(io::IO, model::Model, ::_Temperature) = print(io, "Temperature: $(model.T)K")
