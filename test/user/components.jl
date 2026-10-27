"""
Test every *specific* component behaviour,
not already tested as 'typical components' before.
"""
module TestComponents

# Many small similar components tests files, although they easily diverge.
include("data_components/species.jl")
include("data_components/foodweb.jl")
include("data_components/body_mass.jl")
#  include("data_components/metabolic_class.jl")
include("data_components/temperature.jl")
#  include("data_components/growth_rate.jl")
#  include("data_components/hill_exponent.jl")

# XXX: check that no test file is left unrun.

end
