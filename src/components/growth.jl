"""
Growth rates for every *producer* in the model.
Like body masses, growth rates mass are either given as-is by user
or they are calculated from other components if given correct allometric rates.
Interestingly, allometric rates are either self-sufficient,
or they require that a temperature be defined within the model.
"""
module GrowthDef

using EcologicalNetworksDynamics.Interface: EN, SL, IT, Allometry, @alias

const s, S = SL.NodeField(:producers, :growth)
SL.name_variants(::S) = (:growth, :growth, :Growth, :Growth, :r)
SL.type(::S) = Float64
IT.early_check(::S, r::Real) = IT.non_negative(Float64, r)

# Allometry blueprints.
miele2019() = Allometry(; producer = (a = 1, b = -1 / 4))
binzer2016() =
    (E_a = -0.84, allometry = Allometry(; producer = (a = exp(-15.68), b = -0.25)))
albp = IT.define_allometry_blueprints(EN, s;
    base = :Miele2019 => miele2019(),
    temperature = :Binzer2016 => binzer2016(),
)

# Component.
const Growth, _Growth = IT.define_node_field_component(EN, s; blueprints = [albp])
@alias r producers.growth

# Default constructor.
(::_Growth)(default::Symbol) = IT.from_name(default,
    :Miele2019 => () -> Growth.Allometric(default),
    :Binzer2016 => () -> Growth.Temperature(default),
    ; s)

end

local Growth, _Growth # (reassure JuliaLS)
export Growth
