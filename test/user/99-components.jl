# Test every component behaviour/views specificities,
# not already tested as 'typical components' before.

module TestComponents

# Many small similar components tests files, although they easily diverge.
only = [
    "./data_components/species.jl",
    "./data_components/foodweb.jl",
    "./data_components/body_mass.jl",
    # HERE: have it work.
    #  "./data_components/metabolic_class.jl",
] # Only run these if specified.
if isempty(only)
    for subfolder in ["./data_components", "./code_components"]
        for (folder, _, files) in walkdir(joinpath(dirname(@__FILE__), subfolder))
            for file in files
                path = joinpath(folder, file)
                if !endswith(path, ".jl")
                    continue
                end
                include(path)
            end
        end
    end
else
    for file in only
        include(file)
    end
end

end
