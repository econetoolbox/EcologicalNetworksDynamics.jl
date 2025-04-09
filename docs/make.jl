using EcologicalNetworksDynamics
using Documenter

# TODO: extract doctests from Internals and run them.

makedocs(;
    modules = [EcologicalNetworksDynamics],
    authors = "Eva Delmas" *
              ", Ismaël Lajaaiti" *
              ", Thomas Malpas" *
              ", Hana Mayall" *
              ", Iago Bonnici" *
              ", Sonia Kéfi" *
              ", Andrew Beckerman",
    repo = "https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/blob/{commit}{path}#{line}",
    sitename = "EcologicalNetworksDynamics.jl",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        assets = String[],
    ),
    pages = [
        "Welcome" => "index.md",
        "Guide" => [
            "Quick Start" => "man/quickstart.md",
            "The Model and its Components" => "man/components.md",
            "Generate Food Webs" => "man/foodwebs.md",
            "Build Simple Models" => "man/simple-models.md",
            "Build Advanced Models" => "man/advanced-models.md",
            "Simulate the Community Dynamics" => "man/simulate.md",
            "Analyse the Simulated Dynamics" => "man/output-analysis.md",
            "Stability Analysis" => "man/stability.md",
        ],
        #  "Tutorials" => [
        #  "Paradox of enrichment" => "example/paradox_enrichment.md",
        #  "Intraspecific competition and stability" => "example/intracomp_stability.md",
        #  ],
        "Library" => ["Public" => "lib/public.md", "Internals" => "lib/internals.md"],
    ],
    #  TODO: restore the following limitations to:
    doctest = false, #  true
    checkdocs = :exports, #  :all
    warnonly = true, #  false
    doctestfilters = [
        # Common source of noise in the doctests.
        r" (alias for EcologicalNetworksDynamics.Framework.System{<inner parms>})",
    ],
)

deploydocs(;
    repo = "github.com/econetoolbox/EcologicalNetworksDynamics.jl",
    devbranch = "doc",
)
