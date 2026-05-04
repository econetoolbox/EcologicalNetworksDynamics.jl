# Temperature is a single graph-level scalar
# useful to calculate allometric values for various biorates.

# (reassure JuliaLS)
(false) && (local Temperature, _Temperature)

# Typical, vanilla graph scalar component.
d = D.GraphField(:temperature)
DT = typeof(d)
D.name_variants(::DT) = (:T, :temperature, :Temperature)
D.type(::DT) = Float64
NF.check(::DT, input) = NF.non_negative(Float64, input)

NF.define_graph_scalar(EN, d)
export Temperature

# Default value.
(::_Temperature)() = Temperature.Raw(293.15)
