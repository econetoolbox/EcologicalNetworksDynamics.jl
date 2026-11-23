module CarryingCapacityDef

using EcologicalNetworksDynamics.Interface: EN, SL, IT, Allometry, @alias

const s, S = SL.NodeField(:producers, :carrying_capacity)
SL.name_variants(::S) = (
    :carrying_capacity,
    :carrying_capacities,
    :CarryingCapacity,
    :CarryingCapacities,
    :K,
)
SL.type(::S) = Float64
IT.early_check(::S, K::Real) = IT.non_negative(Float64, K)

# Allometry blueprint (temperature only).
# TODO: since only producers are involved,
# does it make sense to receive and process a full allometric dict here?
binzer2016() = (E_a = 0.71, allometry = Allometry(; producer = (a = 3, b = 0.28)))
albp = IT.define_allometry_blueprints(EN, s; temperature = binzer2016())
IT.construct(::Type{albp.Temperature}, lit::Symbol) =
    IT.from_name(lit, :Binzer2016 => binzer2016)

const CarryingCapacity, _CarryingCapacity =
    IT.define_node_field_component(EN, s; blueprints = [albp])

(::_CarryingCapacity)(default::Symbol) = IT.from_name(default,
    :Binzer2016 => () -> CarryingCapacity.Temperature(default),
    ; s)

@alias K carrying_capacity
@alias producers.carrying_capacity K

end
local CarryingCapacity, _CarryingCapacity # (reassure JuliaLS)
export CarryingCapacity
