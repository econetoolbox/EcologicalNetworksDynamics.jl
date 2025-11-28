module TestFramework

# Raise the hack flag to test macros within @testset local scopes.
using EcologicalNetworksDynamics.Framework

# Run all numbered -.jl files we can find by default, except the current one.
only = [] # Unless some files are specified here, in which case only run these.
if isempty(only)
    for (folder, _, files) in walkdir(dirname(@__FILE__))
        for file in files
            path = joinpath(folder, file)
            if !endswith(path, ".jl") ||
               (abspath(path) == @__FILE__) ||
               !startswith(basename(path), r"[0-9]")
                continue
            end
            include(path)
        end
    end
else
    for file in only
        include(file)
    end
end

end
