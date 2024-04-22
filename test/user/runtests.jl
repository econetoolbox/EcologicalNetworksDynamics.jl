module TestUser

using EcologicalNetworksDynamics
using Random
using Test
using ..TestFailures
using ..TestTopologies

Value = EcologicalNetworksDynamics.InnerParms # To make @sysfails work.
import ..Main: @sysfails, @argfails

# Run all .jl files we can find except the current one (and without recursing).
only = [] # Unless some files are specified here, in which case only run these.
if isempty(only)
    folder = dirname(@__FILE__)
    for file in readdir(folder)
        path = joinpath(folder, file)
        if !endswith(path, ".jl") || (abspath(path) == @__FILE__)
            continue
        end
        include(path)
    end
else
    for file in only
        include(file)
    end
end

end
