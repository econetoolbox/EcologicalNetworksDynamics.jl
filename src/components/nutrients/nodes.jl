module NodesDef

using EcologicalNetworksDynamics: Nutrients
using EcologicalNetworksDynamics.Interface:
    EN, ST, SL, IT, CS, Blueprint, Model, @bp_construct

const s, S = SL.Class(:nutrients)
SL.name_variants(::S) = (:n, :nutrient, :nutrients, :Nutrient, :Nutrients)
SL.componentname(::S) = :Nodes # Not to clash with wrapping 'Nutrients' module.

"Construct `n` nutrient node per producer in the foodweb."
mutable struct PerProducer <: Blueprint
    n::Int
    @bp_construct PerProducer
    PerProducer() = PerProducer(1)
end
IT.register_blueprint(PerProducer, "producers in the foodweb"; s, depends = [EN.Foodweb])
IT.cst_early_check(::PerProducer, n) = IT.non_negative(Int, n)

function IT.expand!(md::Model, ::PerProducer, n)
    n_nutrients = n * md.producers.count
    IT.expand!(md, s, n_nutrients)
end

const Nodes, _Nodes = IT.define_class_component(Nutrients, s; blueprints = [PerProducer])

# In the presence of trophic links, all producers become connected to all nutrient nodes.
function nutrients_producers!(nw, md)
    P, N = md.producers.count, md.nutrients.count
    ST.add_web!(nw, :nutrients_producers, (:producers, :nutrients), ST.FullForeign(P, N))
end
CS.add_trigger!([EN.Foodweb, Nodes], nutrients_producers!)

end
local Nodes, _Nodes # (reassure JuliaLS)
# Don't export to encourage disambiguated access as `Nutrients.Nodes`.
