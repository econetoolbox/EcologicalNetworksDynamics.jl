@testset "Classic response component." begin

    Random.seed!(12)

    base = Model(Foodweb(:niche; S = 5, C = 0.2), MetabolicClass(:all_invertebrates))

    # Code component blueprint brings all required data components with it..
    clr = ClassicResponse()
    @test !does_bring(clr.M) # .. except for the body mass.
    @test clr.w == ConsumersPreferences(:homogeneous)
    @test clr.h == HillExponent(2)
    @test embedded(clr.handling_time) isa HandlingTime.Miele2019

    # The body mass is typically brought another way.
    bm = BodyMass(1) # (use constant mass to ease later tests)

    m = base + bm + clr
    @test m.h == 2
    @test m.M == ones(5)
    @test m.intraspecific_interference == zeros(5)
    @test m.attack_rate == 50 * m.A
    @test m.handling_time == 0.3 * m.A
    q = 0.5
    @test m.w == [
        0 0 0 q q
        q q 0 0 0
        0 0 0 0 1
        0 0 0 0 0
        0 0 0 0 0
    ]
    a, b = 0.45, 0.85
    @test m.e == [
        0 0 0 a a
        b b 0 0 0
        0 0 0 0 a
        0 0 0 0 0
        0 0 0 0 0
    ]

    # Customize sub-blueprints:
    clr = ClassicResponse(; M = (; Z = 1.5))
    @test clr.M.Z == 1.5
    @test clr.w == ConsumersPreferences(:homogeneous)
    @test clr.h == HillExponent(2)
    @test clr.handling_time == HandlingTime(:Miele2019)

    m = base + clr
    @test m.h == 2
    @test m.M ≈ clr.M.Z .^ (m.trophic.levels .- 1)
    @test m.intraspecific_interference == zeros(5)
    @test round.(m.attack_rate) ≈ [
        0 0 0 60 60
        56 54 0 0 0
        0 0 0 0 60
        0 0 0 0 0
        0 0 0 0 0
    ]
    @test round.(100 * m.handling_time) ≈ [
        0 0 0 25 25
        22 26 0 0 0
        0 0 0 0 25
        0 0 0 0 0
        0 0 0 0 0
    ]
    q = 0.5
    @test m.w == [
        0 0 0 q q
        q q 0 0 0
        0 0 0 0 1
        0 0 0 0 0
        0 0 0 0 0
    ]
    a, b = 0.45, 0.85
    @test m.e == [
        0 0 0 a a
        b b 0 0 0
        0 0 0 0 a
        0 0 0 0 0
        0 0 0 0 0
    ]

    # Cannot bring blueprints if corresponding components are already there.
    @sysfails(
        base + BodyMass(3) + ClassicResponse(; M = 4),
        Add(
            BroughtAlreadyInValue,
            BodyMass,
            [BodyMass.Flat, false, ClassicResponse.Blueprint],
        ),
    )

    # In this situation, just stop bringing.
    m = base + BodyMass(3) + ClassicResponse(; M = nothing) # (which happens to be the default here)
    @test m.M == [3, 3, 3, 3, 3]

end
