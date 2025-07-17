module TestLogisticGrowth
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "Logistic growth component." begin

    Random.seed!(12)

    base = Model(
        Foodweb(:niche; S = 5, C = 0.2),
        BodyMass(1),
        MetabolicClass(:all_invertebrates),
    )

    # Code component blueprint brings all required data components with it.
    lg = LogisticGrowth()
    @test lg.r.allometry[:p][:a] == 1
    @test lg.K == CarryingCapacity(1)
    @test lg.producers_competition.diag == 1
    @test lg.producers_competition.off == 0

    m = base + lg
    @test m.r == [0, 0, 0, 1, 1]
    @test m.K == [0, 0, 0, 1, 1]
    @test m.producers.competition.matrix == [
        0 0 0 0 0
        0 0 0 0 0
        0 0 0 0 0
        0 0 0 1 0
        0 0 0 0 1
    ]

    # Customize sub-blueprints:
    lg = LogisticGrowth(; producers_competition = (; diag = 2, off = 1))
    @test lg.r.allometry[:p][:a] == 1
    @test lg.K == CarryingCapacity(1)
    @test lg.producers_competition.diag == 2
    @test lg.producers_competition.off == 1

    m = base + lg
    @test m.r == [0, 0, 0, 1, 1]
    @test m.K == [0, 0, 0, 1, 1]
    @test m.producers.competition.matrix == [
        0 0 0 0 0
        0 0 0 0 0
        0 0 0 0 0
        0 0 0 2 1
        0 0 0 1 2
    ]

    # Cannot bring blueprints if corresponding components are already there.
    @sysfails(
        base + GrowthRate(5) + LogisticGrowth(; r = 1),
        Add(
            BroughtAlreadyInValue,
            GrowthRate,
            [GrowthRate.Flat, false, LogisticGrowth.Blueprint],
        )
    )

    # In this situation, just stop bringing.
    m = base + GrowthRate(5) + LogisticGrowth(; r = nothing)
    @test m.r == [0, 0, 0, 5, 5]

    # If you don't bring, make sure the target model completes your incomplete blueprint.
    @sysfails(
        base + LogisticGrowth(; r = nothing),
        Missing(GrowthRate, LogisticGrowth, [LogisticGrowth.Blueprint], nothing),
    )

end

end
