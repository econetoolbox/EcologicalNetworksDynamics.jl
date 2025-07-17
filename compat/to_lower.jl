# For conditional inclusion from `test/runtests.jl`.

using Pkg
using EcologicalNetworksDynamics
using TOML

println("Extract all lower bounds from the [compat] section.")
toml = joinpath(dirname(dirname(pathof(EcologicalNetworksDynamics))), "Project.toml")
toml = TOML.parsefile(toml)
lowest(v) = String(first(split(v, ", ")))
lower = [
    Pkg.PackageSpec(; name, version = lowest(v)) for
    (name, v) in toml["compat"] if name != "julia"
]

println("Force-pin environment down to them.")
Pkg.pin(lower)
Pkg.status(; mode = PKGMODE_MANIFEST)
