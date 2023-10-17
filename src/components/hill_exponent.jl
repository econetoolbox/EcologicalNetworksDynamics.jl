# Set or generate hill-exponent.

# (reassure JuliaLS)
(false) && (local HillExponent, _HillExponent)

# ==========================================================================================
# Blueprints.

module HillExponent_
include("blueprint_modules.jl")

#-------------------------------------------------------------------------------------------
# From raw value.

mutable struct Raw <: Blueprint
    h::Float64
end
@blueprint Raw "power value"
export Raw

F.early_check(bp::Raw) = check(bp.h)
check(h) = check_value(>=(0), h, nothing, :h, "Not a positive (power) value")

F.expand!(raw, bp::Raw) = raw._scratch[:hill_exponent] = bp.h

end

# ==========================================================================================
# Component and generic constructors.

@component HillExponent{Internal} blueprints(HillExponent_)
export HillExponent

(::_HillExponent)(h) = HillExponent.Raw(h)

@expose_data graph begin
    property(hill_exponent, h)
    depends(HillExponent)
    get(raw -> raw._scratch[:hill_exponent])
    set!((raw, rhs::Real) -> begin
        HillExponent_.check(rhs)
        h = Float64(rhs)
        raw._scratch[:hill_exponent] = h
        # Legacy updates, required because scalars don't alias.
        # Should not be needed once the Internals have been refactored.
        fr = raw.functional_response
        fr isa Internals.BioenergeticResponse && (fr.h = h)
        fr isa Internals.ClassicResponse && (fr.h = h)
    end)
end

# Display.
F.shortline(io::IO, model::Model, ::_HillExponent) = print(io, "Hill Exponent: $(model.h)")
