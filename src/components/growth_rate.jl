# Set or generate growth rates for every *producer* in the model.

# Like body masses, growth rates mass are either given as-is by user
# or they are calculated from other components if given correct allometric rates.
# Interestingly, allometric rates are either self-sufficient,
# or they require that a temperature be defined within the model.

(false) && (local GrowthRate, _GrowthRate) # (reassure JuliaLS)
export GrowthRate

module GrowthRateDef

using EcologicalNetworksDynamics: EN, D, NF, Allometry, @alias

const d = D.SparseNodeField(:producers, :growth, :species)
const DT = typeof(d)

D.name_variants(::DT) = (:growth_rate, :growth_rates, :GrowthRate, :GrowthRates, :r)
D.type(::DT) = Float64
NF.check(::DT, input) = NF.non_negative(Float64, input)

# Allometry blueprints.
miele2019() = Allometry(; producer = (a = 1, b = -1 / 4))
binzer2016() =
    (E_a = -0.84, allometry = Allometry(; producer = (a = exp(-15.68), b = -0.25)))
albp = EN.define_allometry_blueprints(EN, d, miele2019(), binzer2016())

# Codegen + exec.
NF.define_sparse_node_field_component(EN, d; blueprints = [albp])
using .EN: GrowthRate, _GrowthRate

@alias producers.growth growth_rate

# Forward to default constructor.
(::_GrowthRate)(default::Symbol) = NF.from_name(
    default,
    :Miele2019 => () -> GrowthRate.Allometric(default),
    :Binzer2016 => () -> GrowthRate.Temperature(default),
)
EN.construct(::DT, ::Type{GrowthRate.Allometric}, lit::Symbol) =
    NF.from_name(lit, :Miele2019 => miele2019)
EN.construct(::DT, ::Type{GrowthRate.Temperature}, lit::Symbol) =
    NF.from_name(lit, :Binzer2016 => binzer2016)

end
