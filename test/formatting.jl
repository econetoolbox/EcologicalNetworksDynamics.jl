module TestFormatting

using EcologicalNetworksDynamics
using JuliaFormatter
using Crayons

@info "Checking source code formatting..\n"

root = pkgdir(EcologicalNetworksDynamics)

exclude = [
    # Not formatted according to JuliaFormatter.
    "README.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    # Wait on https://github.com/JuliaDocs/Documenter.jl/issues/2025 or the end of boost warnings.
    "docs/src/man/boost.md",
    # Wait on https://github.com/JuliaDocs/Documenter.jl/issues/1420.
    "docs/src/man/components.md",
    "docs/src/man/simple-models.md",
    # Breaks the nested markdown list in docstring?
    "src/components/foodweb.jl",
    # TODO: stop excluding the above when possible.
]

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

any_wrong = Ref(false)
textwidth = 80
for (folder, _, files) in walkdir(root)
    for file in files
        path = joinpath(folder, file)
        display_path = strip_root(path)
        if display_path in exclude
            continue
        end
        if !any(endswith(file, ext) for ext in [".jl", ".md", ".jmd", ".qmd"])
            continue
        end
        n = length(display_path)
        print("\r$display_path" * repeat(" ", textwidth - length(display_path)))
        if !format(path; overwrite = false, format_markdown = true)
            config_path = joinpath(basename(dirname(abspath(".."))), ".JuliaFormatter.toml")
            dev_path = escape_string(abspath(path))
            short_path = chopprefix(dev_path, abspath(root) * '/')
            b = crayon"blue"
            r = crayon"reset"
            println()
            @warn "Source code in $b$short_path$r is not formatted according \
            to the project style defined in $config_path. \
            Consider formatting it using your editor's autoformatter or with:\n  \
                julia> using JuliaFormatter;\n  \
                julia> format(\"$dev_path\", format_markdown=true)\n"
            any_wrong[] = true
        end
    end
end
if !any_wrong[]
    print("\r")
    @info "Project sources correctly formatted. ✔"
else
    println("\r" * repeat(" ", textwidth))
end

end
