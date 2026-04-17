module TestInput

# What user should only need to import.
using EcologicalNetworksDynamics

using SparseArrays
using Random
using Test

# Technical additial imports for testing.
import Main: @sysfails, @failswith, @argfails
import EcologicalNetworksDynamics: EN, Network
Value = EN.Network # To make @sysfails work.

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

end
