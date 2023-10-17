@testset "Linear response component." begin

    Random.seed!(12)

    base = Model(Foodweb(:niche; S = 5, C = 0.2))

    # Code component blueprint brings all required data components with it.
    lr = LinearResponse()
    @test lr.alpha == ConsumptionRate(1)
    @test lr.w == ConsumersPreferences(:homogeneous)

    m = base + lr
    @test m.alpha == [1, 1, 1, 0, 0]
    h = 0.5 # "half"
    @test m.w == [
        0 0 0 h h
        h h 0 0 0
        0 0 0 0 1
        0 0 0 0 0
        0 0 0 0 0
    ]

    # Customize sub-blueprints:
    lr = LinearResponse(; alpha = [1, 2, 0, 0, 0])
    @test lr.alpha == ConsumptionRate([1, 2, 0, 0, 0])
    @test lr.w == ConsumersPreferences(:homogeneous)

    m = base + lr
    @test m.alpha == [1, 2, 0, 0, 0]
    q = 0.5
    @test m.w == [
        0 0 0 q q
        q q 0 0 0
        0 0 0 0 1
        0 0 0 0 0
        0 0 0 0 0
    ]

    # Cannot bring blueprints if corresponding components are already there.
    @sysfails(
        base + ConsumersPreferences(:homogeneous) + LinearResponse(; w = :homogeneous),
        Add(
            BroughtAlreadyInValue,
            ConsumersPreferences,
            [ConsumersPreferences.Homogeneous, false, LinearResponse.Blueprint],
        ),
    )

    # In this situation, just stop bringing.
    m = base + ConsumersPreferences(5 .* m.A) + LinearResponse(; w = nothing)
    @test m.w == [
        0 0 0 5 5
        5 5 0 0 0
        0 0 0 0 5
        0 0 0 0 0
        0 0 0 0 0
    ]

end
