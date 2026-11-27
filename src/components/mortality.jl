module MortalityDef

using EcologicalNetworksDynamics.Interface: EN, SL, IT, Allometry, @alias

const s, S = SL.NodeField(:species, :mortality)
SL.name_variants(::S) = (:mortality, :mortalities, :Mortality, :Mortalities, :d)
SL.type(::S) = Float64
IT.early_check(::S, d::Real) = IT.non_negative(Float64, d)

# Allometry blueprint.
miele2019() = Allometry(;
    producer = (a = 0.0138, b = -1 / 4),
    invertebrate = (a = 0.0314, b = -1 / 4),
    ectotherm = (a = 0.0314, b = -1 / 4),
)
albp = IT.define_allometry_blueprints(EN, s; base = :Miele2019 => miele2019())

const Mortality, _Mortality = IT.define_node_field_component(EN, s; blueprints = [albp])

@alias d species.mortality

(::_Mortality)(default::Symbol) = IT.from_name(default,
    :Miele2019 => () -> Mortality.Allometric(default),
    ; s)

end
local Mortality, _Mortality # (reassure JuliaLS)
export Mortality
