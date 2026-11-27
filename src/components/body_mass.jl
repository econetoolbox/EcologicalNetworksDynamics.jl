module BodyMassDef

using EcologicalNetworksDynamics: Foodweb, argerr
using EcologicalNetworksDynamics.Interface:
    EN, SL, CS, IT, Model, Blueprint, @alias, @bp_construct

const s, S = SL.NodeField(:species, :body_mass)
SL.name_variants(::S) = (:body_mass, :body_masses, :BodyMass, :BodyMasses, :M)
SL.type(::S) = Float64
IT.early_check(::S, mass::Real) = IT.non_negative(Float64, mass)

# ==========================================================================================
# One extra blueprint to build from trophic levels.

mutable struct Z <: Blueprint
    Z::Float64
    @bp_construct Z
end
IT.register_blueprint(Z, "trophic levels"; s, depends = [Foodweb])

function IT.cst_early_check(::Type{Z}, x)
    x >= 0 && return x
    IT.checkerr(x,
        "Cannot calculate body masses from trophic levels with a negative value of Z.")
end

function IT.expand!(md::Model, ::Z, Z)
    M = read(md.trophic._level) do level
        Z .^ (level .- 1) # Credit to Ismaël Lajaaiti.
    end
    IT.expand!(md, s, M)
end

# ==========================================================================================
# Define component.

const BodyMass, _BodyMass = IT.define_node_field_component(EN, s; blueprints = [Z])
@alias M species.body_mass

# Extra constructor dispatch to the extra blueprint.
function (::_BodyMass)(; M = nothing, Z = nothing)
    if isnothing(M) == isnothing(Z)
        isnothing(M) && argerr("Either 'M' or 'Z' must be provided to define body masses.")
        argerr("Cannot specify both 'M' and 'Z' to define body masses.")
    end
    isnothing(Z) ? BodyMass(M) : BodyMass.Z(Z)
end

end
local BodyMass, _BodyMass # (reassure JuliaLS)
export BodyMass
