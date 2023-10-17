@testset "Bioenergetic response component." begin

    Random.seed!(12)

    base = Model(
        Foodweb(:niche; S = 5, C = 0.2),
        BodyMass(1),
        MetabolicClass(:all_invertebrates),
    )

    # Code component blueprint brings all required data components with it.
    ber = BioenergeticResponse()
    @test ber.e.e_herbivorous == 0.45
    @test ber.y.allometry[:i][:a] == 8.0
    @test ber.h == HillExponent(2)

    m = base + ber
    @test m.h == 2
    @test m.y == [8, 8, 8, 0, 0]
    @test m.half_saturation_density == [0.5, 0.5, 0.5, 0, 0]
    @test m.intraspecific_interference == zeros(5)
    h = 0.5 # "half"
    @test m.w == [
        0 0 0 h h
        h h 0 0 0
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
    ber = BioenergeticResponse(; c = [1, 2, 0, 0, 0])
    @test ber.e.e_herbivorous == 0.45
    @test ber.y.allometry[:i][:a] == 8.0
    @test ber.h == HillExponent(2)
    @test ber.c == IntraspecificInterference([1, 2, 0, 0, 0])

    m = base + ber
    @test m.h == 2
    @test m.y == [8, 8, 8, 0, 0]
    @test m.half_saturation_density == [0.5, 0.5, 0.5, 0, 0]
    @test m.intraspecific_interference == [1, 2, 0, 0, 0]

    # Cannot bring blueprints if corresponding components are already there.
    @sysfails(
        base + HillExponent(3) + BioenergeticResponse(; h = 2),
        Add(
            BroughtAlreadyInValue,
            HillExponent,
            [HillExponent.Raw, false, BioenergeticResponse.Blueprint],
        ),
    )

    # In this situation, just stop bringing.
    m = base + HillExponent(3) + BioenergeticResponse(; h = nothing)
    @test m.h == 3

end
