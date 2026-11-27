module ConsumerPreferenceDef

using EcologicalNetworksDynamics.Interface: EN, SL, IT, ST, Blueprint, Model, @alias
using SparseArrays

const s, S = SL.EdgeField(:trophic, :consumer_preference)
SL.name_variants(::S) = (
    :consumer_preference,
    :consumer_preferences,
    :ConsumerPreference,
    :ConsumerPreferences,
    :w,
)
SL.type(::S) = Float64
IT.early_check(::S, w::Real) = IT.non_negative(Float64, w)

#-------------------------------------------------------------------------------------------
"""
Build so that preferences are "homogeneous",
meaning that the predator evenly splits its resource among its preys.

⚠ Warning: This calculation is based on the initial foodweb topology only,
and will *not* be automatically updated upon preys extinctions during simulation.
In addition, it is yet unclear whether this is a proper way
of modelling consumer preferences, as it opts out of the usual mass-action logic
and introduces artifacts within the ODEs.
See: https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/issues/192
"""
mutable struct Homogeneous <: Blueprint end
IT.register_blueprint(Homogeneous, "homogeneous_preferences"; s)

function IT.expand!(md::Model, ::Homogeneous, _)
    (; S) = md
    tp = ST.web(md, s).topology
    w = spzeros(Float64, (S, S))
    for (i_consumer, preys) in ST.forward(tp)
        n_preys = ST.n_targets(tp, i_consumer)
        for (i_prey, _) in preys
            w[i_consumer, i_prey] = 1 / n_preys
        end
    end
    IT.expand!(md, s, w)
end
#-------------------------------------------------------------------------------------------

const ConsumerPreference, _ConsumerPreference =
    IT.define_web_field_component(EN, s; blueprints = [Homogeneous])

@alias w trophic.consumer_preference
@alias consumers.preference w

end
local ConsumerPreference, _ConsumerPreference # (reassure JuliaLS)
export ConsumerPreference
