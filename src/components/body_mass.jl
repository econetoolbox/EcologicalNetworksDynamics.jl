module BodyMassDef

using EcologicalNetworksDynamics: Foodweb, argerr
using EcologicalNetworksDynamics.NetworkFramework:
    EN, D, F, NF, Blueprint, @alias

const d, _D = D.NodeField(:species, :body_mass)
D.name_variants(::_D) = (:body_mass, :body_masses, :BodyMass, :BodyMasses, :M)
D.type(::_D) = Float64
NF.intrinsic_check(::_D, mass) = NF.non_negative(Float64, mass)

# One extra blueprint to build from trophic levels.
mutable struct Z <: Blueprint
    Z::Float64
end
NF.define_blueprint(Z, "trophic levels"; depends = [Foodweb])

NF.define_node_field_component(EN, d; blueprints = [:Z => Z])
local BodyMass, _BodyMass # (reassure JuliaLS)
@alias M body_mass

# Extra constructor dispatch to the extra blueprint.
function (::_BodyMass)(; M = nothing, Z = nothing)
    if isnothing(M) == isnothing(Z)
        isnothing(M) && argerr("Either 'M' or 'Z' must be provided to define body masses.")
        argerr("Cannot specify both 'M' and 'Z' to define body masses.")
    end
    isnothing(Z) ? BodyMass(M) : BodyMass.Z(Z)
end

function F.early_check(bp::Z)
    (; Z) = bp
    Z >= 0 || NF.checkerr(
        Z,
        "Cannot calculate body masses from trophic levels \
         with a negative value of Z.",
    )
end

function F.expand!(model, bp::Z)
    M = read(model.trophic._level) do level
        bp.Z .^ (level .- 1) # Credit to Ismaël Lajaaiti.
    end
    NF.expand!(d, model, M)
end

end
local BodyMass, _BodyMass # (reassure JuliaLS)
export BodyMass
