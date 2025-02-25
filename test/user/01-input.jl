module TestInput

using EcologicalNetworksDynamics
using SparseArrays
using Random
using Test

Value = EcologicalNetworksDynamics.Internal # To make @sysfails work.
import ..Main: @sysfails, @failswith, @argfails

const EN = EcologicalNetworksDynamics

# Components input is supposed to be flexible but checked.
# Check these here, by testing various inputs either supposed to error
# or to be equivalent to the defaults.

# Must of this logic
# is actually implemented and tested within the GraphDataInputs submodule
# and process_kwargs helpers.
# As a consequence, don't repeat all these tests
# for every typical use of these utils here,
# and focus on other components specificities in the next.

# ==========================================================================================
@testset "Simple components as a typical examples of GraphDataInput." begin

    #---------------------------------------------------------------------------------------
    # Constructor input types.

    base = Model(Foodweb([:a => [:b, :c], :b => :c]))

    # Implicit scalar conversion.
    he = HillExponent(2)
    @test he.h == 2.0
    @test he.h isa Float64

    # Implicit uniform vectors.
    bm = BodyMass(2)
    @test bm.M == 2 # Scalar in the blueprint.
    @test bm.M isa Float64
    model = base + bm
    @test model.M == [2.0, 2.0, 2.0] # Vector in the model
    @test model.M._ref isa Vector{Float64}

    # Explicit vector with conversion require that a fresh copy
    # be constructed within the blueprint.
    raw = [2, 2, 2]
    bm = BodyMass(raw) # Converted.
    @test bm.M == [2.0, 2.0, 2.0]
    @test bm.M isa Vector{Float64}
    # So we can't modify the blueprint from the original reference.
    raw[1] = 3
    @test raw == [3, 2, 2]
    @test bm.M == [2, 2, 2] # Unchanged.

    # Explicit vector without conversion get aliased to user input.
    raw = [2.0, 2.0, 2.0]
    bm = BodyMass(raw)
    @test bm.M === raw
    # So we get to modify the blueprint from original reference.
    raw[1] = 3
    @test raw == [3, 2, 2]
    @test bm.M == [3, 2, 2] # Updated.
    # But no reference is leaked from inner model.
    model = base + bm
    @test !(model.M === raw)
    # So we can modify the blueprint, but not the model this way.
    raw[2] = 4
    @test bm.M == [3, 4, 2] # Updated.
    @test model.M == [3, 2, 2] # Safe.

    # Symbol input to generate default data.
    cp = ConsumersPreferences("homogeneous")
    @test cp isa ConsumersPreferences.Homogeneous
    model = base + cp
    @test model.w == [
        0 0.5 0.5
        0 0 1
        0 0 0
    ]

    # Note that a blueprint may be corrupted.
    h = HillExponent(-1)
    @test h.h == -1
    # But then it is rejected prior to expansion.
    @sysfails(
        # "Early" rejection, because of internal blueprint inconsistency.
        base + h,
        Check(early, [HillExponent.Raw], "Not a positive (power) value: h = -1.0.")
    )
    bm = BodyMass([1, 2])
    @sysfails(
        # "Late" rejection, because of a mismatch between blueprint and model values.
        base + bm,
        Check(
            late,
            [BodyMass.Raw],
            "Invalid size for parameter 'M': expected (3,), got (2,).",
        )
    )

    # Typical type errors.
    @argfails(
        BodyMass("nope"),
        "Error while attempting to convert 'M' \
         to ref-value map for 'Float64' data \
         (details further down the stacktrace). \
         Received \"nope\" ::$String."
    )

    @argfails(
        ConsumersPreferences([1, 5]),
        "Error while attempting to convert 'w' \
         to adjacency list for 'Float64' data \
         (details further down the stacktrace). \
         Received [1, 5] ::$Vector{$Int64}.",
    )

end

# ==========================================================================================
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
