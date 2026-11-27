module MetabolismDef

using EcologicalNetworksDynamics.Interface: EN, SL, IT, Allometry, @alias

const s, S = SL.NodeField(:species, :metabolism)
SL.name_variants(::S) = (:metabolism, :metabolism, :Metabolism, :Metabolism, :x)
SL.type(::S) = Float64
IT.early_check(::S, x::Real) = IT.non_negative(Float64, x)

# Allometry blueprints.
miele2019() = Allometry(;
    producer = (a = 0, b = 0),
    invertebrate = (a = 0.314, b = -1 / 4),
    ectotherm = (a = 0.88, b = -1 / 4),
)
binzer2016() = (
    E_a = -0.69,
    allometry = Allometry(;
        producer = (a = 0, b = -0.31), # ? Is that intended @hanamayall?
        invertebrate = (a = exp(-16.54), b = -0.31),
        ectotherm = (a = exp(-16.54), b = -0.31),
    ),
)
albp = IT.define_allometry_blueprints(EN, s;
    base = :Miele2019 => miele2019(),
    temperature = :Binzer2016 => binzer2016(),
)

const Metabolism, _Metabolism = IT.define_node_field_component(EN, s; blueprints = [albp])

@alias x species.metabolism

(::_Metabolism)(default::Symbol) = IT.from_name(default,
    :Miele2019 => () -> Metabolism.Allometric(default),
    :Binzer2016 => () -> Metabolism.Temperature(default),
    ; s)

end
local Metabolism, _Metabolism # (reassure JuliaLS)
export Metabolism
