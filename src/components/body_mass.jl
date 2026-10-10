module BodyMassDef

using EcologicalNetworksDynamics: Foodweb, argerr
using EcologicalNetworksDynamics.NetworkFramework:
    EN, D, F, NF, Model, Blueprint, @alias, @bp_construct

const d, _D = D.NodeField(:species, :body_mass)
D.name_variants(::_D) = (:body_mass, :body_masses, :BodyMass, :BodyMasses, :M)
D.type(::_D) = Float64
NF.intrinsic_check(::_D, mass) = NF.non_negative(Float64, mass)

# ==========================================================================================
# One extra blueprint to build from trophic levels.

mutable struct Z <: Blueprint
    Z::Float64
    @bp_construct Z
end
NF.register_blueprint(Z, "trophic levels"; depends = (Foodweb,))

function NF.early_check(bp::Z)
    (; Z) = bp
    Z >= 0 || NF.checkerr(Z,
        "Cannot calculate body masses from trophic levels \
         with a negative value of Z.")
end

function NF.expand!(m::Model, bp::Z)
    M = read(m.trophic._level) do level
        bp.Z .^ (level .- 1) # Credit to Ismaël Lajaaiti.
    end
    NF.expand!(d, m, M)
end

# ==========================================================================================
# Define component.

const BodyMass, _BodyMass = NF.define_node_field_component(EN, d; blueprints = [:Z => Z])
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
