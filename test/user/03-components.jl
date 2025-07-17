# Test every component behaviour/views specificities.
# Try not to repeat tests already covered by the view/input tests,
# and in general tests covering similar inner calls
# to @component/@method/@expose_data macros/@kwargs_helpers.

module TestComponents

# Many small similar components tests files, although they easily diverge.
only = [] # Only run these if specified.
if isempty(only)
    paths = []
    for subfolder in ["data_components", "code_components"]
        for (folder, _, files) in walkdir(joinpath(dirname(@__FILE__), subfolder))
            for file in files
                path = joinpath(folder, file)
                if !endswith(path, ".jl")
                    continue
                end
                push!(paths, path)
            end
        end
    end
    Main.run_tests(paths; parallel = false) # Not a speedup :(
else
    for file in only
        include(file)
    end
end

end
