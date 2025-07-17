import CompatHelperLocal
using Crayons
using Test
blue = crayon"blue"
bold = crayon"bold"
green = crayon"green"
reset = crayon"reset"

# Display a separator.
sep(mess) = println("$blue$bold== $mess $(repeat("=", 80 - 4 - length(mess)))$reset")

# Display project paths without their root prefix.
root = pkgdir(EcologicalNetworksDynamics)
function strip_root(path::Vector{String})
    proot = splitpath(root)
    for (i, (p, r)) in enumerate(zip(path, proot))
        if p != r
            return path[i:end]
        end
    end
    path[length(proot)+1:end]
end
strip_root(path::String) = joinpath(strip_root(splitpath(path)))

# Spawn a bunch of test files in parallel,
# assuming they all define their own module with no data race.
function run_tests(paths; parallel = false, prefix = nothing)
    @time if parallel
        if !isnothing(prefix)
            # The base folder seems reset within threads?
            paths = joinpath.(prefix, paths)
        end
        Threads.@threads for path in paths
            stripped = strip_root(path)
            println("Launch $(blue)$(stripped)$(reset)..")
            include(path)
            println("$(green)$(bold)PASSED$(reset): $(blue)$(stripped)$(reset)")
        end
    else
        for path in paths
            stripped = strip_root(path)
            println("Test $(blue)$(stripped)$(reset)..")
            include(path)
            println("$(green)$(bold)PASSED$(reset).")
        end
    end
end

# Having correct 'show'/display implies that numerous internals are working correctly.
function check_display(top, short, long)
    @test "$top" == short
    io = IOBuffer()
    show(IOContext(io, :limit => true, :displaysize => (20, 40)), "text/plain", top)
    @test String(take!(io)) == long
end

