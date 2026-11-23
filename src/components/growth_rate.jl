"""
Growth rates for every *producer* in the model.
Like body masses, growth rates mass are either given as-is by user
or they are calculated from other components if given correct allometric rates.
Interestingly, allometric rates are either self-sufficient,
or they require that a temperature be defined within the model.
"""
module GrowthRateDef

using EcologicalNetworksDynamics.Interface: EN, SL, IT, Allometry, @alias

const s, S = SL.NodeField(:producers, :growth)
SL.name_variants(::S) = (:growth_rate, :growth_rates, :GrowthRate, :GrowthRates, :r)
SL.type(::S) = Float64
IT.early_check(::S, growth::Real) = IT.non_negative(Float64, growth)

# ==========================================================================================
# Allometry blueprints.

miele2019() = Allometry(; producer = (a = 1, b = -1 / 4))
binzer2016() =
    (E_a = -0.84, allometry = Allometry(; producer = (a = exp(-15.68), b = -0.25)))
albp = IT.define_allometry_blueprints(EN, s; base = miele2019(), temperature = binzer2016())

IT.construct(::Type{albp.Allometric}, lit::Symbol) =
    (IT.from_name(lit, :Miele2019 => miele2019),)
IT.construct(::Type{albp.Temperature}, lit::Symbol) =
    IT.from_name(lit, :Binzer2016 => binzer2016)

# ==========================================================================================
# Component.

const GrowthRate, _GrowthRate = IT.define_node_field_component(EN, s; blueprints = [albp])

@alias producers.growth growth_rate
# TODO: is 'r' desired as an alias?

# Default constructor.
(::_GrowthRate)(default::Symbol) = IT.from_name(default,
    :Miele2019 => () -> GrowthRate.Allometric(default),
    :Binzer2016 => () -> GrowthRate.Temperature(default),
    ; s)

end

local GrowthRate, _GrowthRate # (reassure JuliaLS)
export GrowthRate
