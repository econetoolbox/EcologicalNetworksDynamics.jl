# This component is (for now) only used
# to define the data required for AttackRate.Miele2019 to work.
module MobilityDef
using EcologicalNetworksDynamics.Interface: EN, SL, IT, Blueprint, Model

const s, S = SL.NodeField(:species, :mobility)
SL.name_variants(::S) = (:mobility, :mobilities, :Mobility, :Mobilities, :mob)
SL.type(::S) = Symbol
IT.early_check(::S, mob::Symbol) = IT.name_among((:sessile, :mobile), mob)

"Default to producers being sessile and consumers being mobile."
struct Miele2019 <: Blueprint end
IT.register_blueprint(Miele2019, "trophic status"; s, depends = [EN.Foodweb])
function IT.expand!(md::Model, ::Miele2019, _)
    var = [isprod ? :sessile : :mobile for isprod in md.producers.mask]
    IT.expand!(md, s, var)
end

const Mobility, _Mobility = IT.define_node_field_component(EN, s; blueprints = [Miele2019])

# Default to this.
(::_Mobility)() = Miele2019()

end
local Mobility, _Mobility # (reassure JuliaLS)
export Mobility


module AttackRateDef

using EcologicalNetworksDynamics.Interface: EN, ST, SL, IT, Blueprint, Allometry, Model

const s, S = SL.EdgeField(:trophic, :attack_rate)
SL.name_variants(::S) = (
    :attack_rate,
    :attack_rates,
    :AttackRate,
    :AttackRates,
    :a_r,
)
SL.type(::S) = Float64
IT.early_check(::S, a_r::Real) = IT.non_negative(Float64, a_r)

#-------------------------------------------------------------------------------------------
"""
Calculate attack rate of predator-prey couples from their body masses,
formally:

  - ``a_{r,ij} = 50 m_i^{0.45} m_j^{0.15}`` if both species are mobiles;
  - ``a_{r,ij} = 50 m_j^{0.15}`` if i is sessile and j mobile;
  - ``a_{r,ij} = 50 m_i^{0.45}`` if j is sessile and i mobile.

This formula is taken from Miele et al. 2019 (PLOS Computational).
"""
struct Miele2019 <: Blueprint end
IT.register_blueprint(Miele2019, "attack rates"; s,
    depends = [EN.BodyMass], implied = [EN.Mobility])
IT.implied(::S, ::EN._Mobility, ::Miele2019) = EN.Mobility()

function IT.expand!(md::Model, ::Miele2019, _)
    # Directly lower into a flattened matrix.
    M, mobility = md.M, md.species.mobility
    tp = ST.web(md, s).topology
    mob(i) = mobility[i] == :mobile # 0 = sessile, 1 = mobile
    vec = [
        attack_rate(M[i], M[j], mob(i), mob(j))
        for (i, j) in ST.edges(tp)
    ]
    IT.expand!(md, s, vec)
end
# Credits to Ismaël Lajaaiti.
attack_rate(M_i, M_j, mob_i, mob_j) = 50 * (M_i^0.45)^mob_i * (M_j^0.15)^mob_j

#-------------------------------------------------------------------------------------------
# Temperature-allometry.
binzer2016() = (
    E_a = -0.38,
    allometry = Allometry(;
        producer = (a = 0, b = 0.25, c = -0.8), # ? Is that intended @hanamayall?
        invertebrate = (a = exp(-13.1), b = 0.25, c = -0.8),
        ectotherm = (a = exp(-13.1), b = 0.25, c = -0.8),
    ),
)
albp = IT.define_allometry_blueprints(EN, s; temperature = :Binzer2016 => binzer2016())
#-------------------------------------------------------------------------------------------

const AttackRate, _AttackRate =
    IT.define_web_field_component(EN, s; blueprints = [Miele2019, albp])

end
local AttackRate, _AttackRate # (reassure JuliaLS)
export AttackRate
