module TestUser

using EcologicalNetworksDynamics
using Random
using Test
using ..TestFailures

Value = EcologicalNetworksDynamics.Internal # To make @sysfails work.
import ..Main: @viewfails, @sysfails, @argfails, @failswith

# Expose to further test submodules.
export Value, @viewfails, @sysfails, @argfails, @failswith

# Run all .jl files we can find except the current one (and without recursing).
only = ["03-components.jl"] # Unless some files are specified here, in which case only run these.
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
