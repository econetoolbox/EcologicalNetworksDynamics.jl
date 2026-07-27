module KwargsHelpersTest

using EcologicalNetworksDynamics
using SparseArrays
using Random

using Test
using Main: @argfails

@testset "Random Foodweb as a typical example of kwargs processing." begin

    Random.seed!(12)

    fw = Foodweb(:niche; S = 5, L = 5)
    @test fw.A == sparse([
        0 0 0 1 1
        1 1 0 0 0
        0 0 0 0 1
        0 0 0 0 0
        0 0 0 0 0
    ])

    fw = Foodweb(:cascade; S = 5, C = 0.2)
    @test fw.A == sparse([
        0 0 0 0 1
        0 0 0 1 1
        0 0 0 1 0
        0 0 0 0 1
        0 0 0 0 0
    ])

    # Guard against missing information.
    @argfails(Foodweb(:niche), "Random foodweb models require a number of species 'S'.")

    # More specific guards.
    @argfails(
        Foodweb(:niche, S = 5),
        "The niche model requires either a connectance value 'C' \
         or a number of links 'L'."
    )
    @argfails(
        Foodweb(:cascade, S = 5),
        "The cascade model requires a connectance value 'C'."
    )

    # Typecheck arguments.
    @argfails(
        Foodweb(:niche, S = 5, L = "notanumber"),
        "Invalid type for argument 'L'. Expected Int64, received: \"notanumber\" ::String.",
    )

    # Catch conversion failures.
    @argfails(
        Foodweb(:niche, S = 5, L = 1.5),
        "Error when converting argument 'L' to Int64. (See further down the stacktrace.)"
    )

    # Forbid certain arguments combinations.
    @argfails(
        Foodweb(:niche, S = 5, L = 3, C = 0.2),
        "Cannot provide both a connectance 'C' and a number of links 'L'."
    )

    # Only expected tol_L if L was given.
    @argfails(
        Foodweb(:niche, S = 5, C = 0.2, tol_L = 0.5),
        "Unexpected argument: tol_L = 0.5."
    )

    # Typecheck arguments with default values.
    @argfails(
        Foodweb(:niche, S = 5, C = 0.2, tol_C = :c),
        "Invalid type for argument 'tol_C'. Expected Float64, received: :c ::Symbol."
    )

end

end
