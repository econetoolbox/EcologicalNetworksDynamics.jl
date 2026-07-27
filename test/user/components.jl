"""
Test every *specific* component behaviour,
not already tested as 'typical components' before.
"""
module TestComponents

# Many small similar components tests files, although they easily diverge.
dir = "./data_components/"
include(dir * "species.jl")
include(dir * "foodweb.jl")
include(dir * "body_mass.jl")
include(dir * "metabolic_class.jl")
include(dir * "temperature.jl")
include(dir * "growth_rate.jl")
include(dir * "hill_exponent.jl")

dir = "./code_components/"

# XXX: check that no test file is left unrun.

end
