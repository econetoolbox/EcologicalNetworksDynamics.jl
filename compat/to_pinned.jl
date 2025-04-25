# For conditional inclusion from `test/runtests.jl`.

using Pkg
using EcologicalNetworksDynamics

base = dirname(dirname(pathof(EcologicalNetworksDynamics)))
env = joinpath(base, "compat", "pinned_test_env")

Pkg.activate(env)
Pkg.instantiate()
