module TestUser

using EcologicalNetworksDynamics
using Random
using Test
using ..TestFailures

const EN = EcologicalNetworksDynamics
Value = EcologicalNetworksDynamics.Internal # To make @sysfails work.
import ..Main: @viewfails, @sysfails, @argfails, @failswith

# Expose to further test submodules.
import .EcologicalNetworksDynamics: WriteError
export Value, @viewfails, @sysfails, @argfails, @failswith, EN, Random, WriteError

# Run all .jl files we can find except the current one (and without recursing).
only = [] # Unless some files are specified here, in which case only run these.
if isempty(only)
    folder = dirname(@__FILE__)
    paths = []
    for file in readdir(folder)
        path = joinpath(folder, file)
        if !endswith(path, ".jl") || (abspath(path) == @__FILE__)
            continue
        end
        push!(paths, path)
    end
    Main.run_tests(paths; parallel = false) # Some parallel within them.
else
    for file in only
        include(file)
    end
end

end
