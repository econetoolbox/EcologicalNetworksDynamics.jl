# For conditional inclusion from `test/runtests.jl`.

using Pkg
using EcologicalNetworksDynamics

println("Activate pinned environment to test within it.")
base = dirname(dirname(pathof(EcologicalNetworksDynamics)))
env = joinpath(base, "compat", "pinned_test_env")

Pkg.activate(env)
Pkg.instantiate()
Pkg.status(; mode = PKGMODE_MANIFEST)
