module BodyMassDef

using EcologicalNetworksDynamics: Foodweb, argerr
using EcologicalNetworksDynamics.NetworkFramework:
    EN, SL, CS, NF, Model, Blueprint, @alias, @bp_construct

const s, S = SL.NodeField(:species, :body_mass)
SL.name_variants(::S) = (:body_mass, :body_masses, :BodyMass, :BodyMasses, :M)
SL.type(::S) = Float64
NF.early_check(::S, mass::Real) = NF.non_negative(Float64, mass)

# ==========================================================================================
# One extra blueprint to build from trophic levels.

mutable struct Z <: Blueprint
    Z::Float64
    @bp_construct Z
end
NF.register_blueprint(Z, "trophic levels"; s, depends = [Foodweb])

function NF.cst_early_check(::Type{Z}, x)
    x >= 0 && return x
    NF.checkerr(x,
        "Cannot calculate body masses from trophic levels with a negative value of Z.")
end

function NF.expand!(md::Model, ::Z, Z)
    M = read(md.trophic._level) do level
        Z .^ (level .- 1) # Credit to Ismaël Lajaaiti.
    end
    NF.expand!(md, s, M)
end

# ==========================================================================================
# Define component.

const BodyMass, _BodyMass = NF.define_node_field_component(EN, s; blueprints = [Z])
@alias M body_mass

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
