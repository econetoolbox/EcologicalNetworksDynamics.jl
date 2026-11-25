module HandlingTimeDef

using EcologicalNetworksDynamics.Interface: EN, SL, IT, ST, Blueprint, Model, Allometry

const s, S = SL.EdgeField(:trophic, :handling_time)
SL.name_variants(::S) = (
    :handling_time,
    :handling_times,
    :HandlingTime,
    :HandlingTimes,
    :h_t,
)
SL.type(::S) = Float64 # TODO: awkward to wind between 'SL' and 'IT' here? Improve?
IT.early_check(::S, h_t::Real) = IT.non_negative(Float64, h_t)

#-------------------------------------------------------------------------------------------
"""
Calculate handling time of a predator-prey couple from by their body masses,
formally: ``h_{t,ij} = 0.3 m_i^{-0.48} m_j^{-0.66}``.
This formula is taken from Miele et al. 2019 (PLOS Computational)
and Rall et al. 2012 (Phil. Tran. R. Soc. B).
"""
struct Miele2019 <: Blueprint end
IT.register_blueprint(Miele2019, "body masses"; s, depends = [EN.BodyMass])

function IT.expand!(md::Model, ::Miele2019, _)
    # Directly lower to a flattened matrix.
    (; body_mass) = md
    tp = ST.web(md, s).topology
    vec = sizehint!(Float64[], ST.n_edges(tp))
    for (i, j) in ST.edges(tp)
        pred, prey = body_mass[i], body_mass[j]
        ht = handling_time(pred, prey)
        push!(vec, ht)
    end
    IT.expand!(md, s, vec)
end
# Credits to Ismaël Lajaaiti.
handling_time(pred_mass, prey_mass) = 0.3 * pred_mass^(-0.48) * prey_mass^(-0.66)

#-------------------------------------------------------------------------------------------
# Allometry.
binzer2016() = (
    E_a = 0.26,
    allometry = Allometry(;
        producer = (a = 0, b = -0.45, c = 0.47), # ? Is that intended @hanamayall?
        invertebrate = (a = exp(9.66), b = -0.45, c = 0.47),
        ectotherm = (a = exp(9.66), b = -0.45, c = 0.47),
    ),
)
albp = IT.define_allometry_blueprints(EN, s; temperature = :Binzer2016 => binzer2016())
#-------------------------------------------------------------------------------------------

const HandlingTime, _HandlingTime =
    IT.define_web_field_component(EN, s; blueprints = [Miele2019, albp])

(::_HandlingTime)(default::Symbol) = IT.from_name(default,
    :Miele2019 => HandlingTime.Miele2019, # Extend for consistency?
    :Binzer2016 => () -> HandlingTime.Temperature(default),
    ; s)

end
local HandlingTime, _HandlingTime # (reassure JuliaLS)
export HandlingTime
