module TestFramework

# Raise the hack flag to test macros within @testset local scopes.
using EcologicalNetworksDynamics.Framework
using Crayons
Framework.LOCAL_MACROCALLS = true

# Run all numbered -.jl files we can find by default, except the current one.
only = [] # Unless some files are specified here, in which case only run these.
if isempty(only)
    paths = []
    for (folder, _, files) in walkdir(dirname(@__FILE__))
        for file in files
            path = joinpath(folder, file)
            if !endswith(path, ".jl") ||
               (abspath(path) == @__FILE__) ||
               !startswith(basename(path), r"[0-9]")
                continue
            end
            push!(paths, path)
        end
    end
    Main.run_tests(paths; parallel = false) # Mostly redundant compilation :(
else
    for file in only
        include(file)
    end
end

Framework.LOCAL_MACROCALLS = false

end
