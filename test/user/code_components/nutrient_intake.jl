module TestNutrientIntake
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "Nutrient intake component." begin

    N = Nutrients

    base = Model(
        Foodweb([:a => :b, :c => [:d, :e]]), # 3 producers.
        BodyMass(1),
        MetabolicClass(:all_invertebrates),
    )

    # Default blueprints.
    ni = NutrientIntake()
    @test ni.nodes == N.Nodes.PerProducer(1)
    @test ni.turnover == N.Turnover(0.25)
    @test ni.r.allometry[:p][:a] == 1
    @test ni.supply == N.Supply(4)
    @test ni.concentration == N.Concentration(0.5)
    @test ni.half_saturation == N.HalfSaturation(0.15)

    m = base + ni
    @test m.nutrients.turnover == [0.25, 0.25, 0.25]
    @test m.nutrients.supply == [4, 4, 4]
    @test m.nutrients.concentration == 0.5 .* ones(3, 3)
    @test m.nutrients.half_saturation == 0.15 .* ones(3, 3)

    # Customize sub-blueprints.
    ni = NutrientIntake(; turnover = [1, 2, 3])
    @test ni.turnover == N.Turnover([1, 2, 3])

    # The exact number of nodes may be specified/brought by the blueprint.
    m = base + NutrientIntake(2)
    @test m.nutrients.names == [:n1, :n2]
    @test m.nutrients.turnover == [0.25, 0.25]
    @test m.nutrients.supply == [4, 4]
    @test m.nutrients.concentration == 0.5 .* ones(3, 2)
    @test m.nutrients.half_saturation == 0.15 .* ones(3, 2)

    m = base + NutrientIntake([:u, :v])
    @test m.nutrients.names == [:u, :v]
    @test m.nutrients.turnover == [0.25, 0.25]

    @test NutrientIntake(2) == NutrientIntake(; nodes = 2)
    @test NutrientIntake([:u, :v]) == NutrientIntake(; nodes = [:u, :v])

    # Don't bring nodes blueprint if it can be implied by another input.
    ni = NutrientIntake(; supply = [1, 2])
    @test !does_bring(ni.nodes)
    @test does_bring(ni.supply)

    # Correct implicit reordering of sub-components.
    # TODO: this should be moved as a pure Framework test.
    m = base + ni # 'Nutrients.Nodes' is expanded *prior* to 'Supply' and 'Turnover'.

    # Watch consistency.
    @argfails(
        NutrientIntake(3; nodes = 2),
        "Nodes specified once as plain argument (3) \
         and once as keyword argument (nodes = 2)."
    )

    @sysfails(
        base + NutrientIntake(3; supply = [1, 2]),
        Check(
            late,
            [N.Supply.Raw, false, NutrientIntake.Blueprint],
            "Invalid size for parameter 's': expected (3,), got (2,).",
        )
    )

    @sysfails(
        base + NutrientIntake(; supply = [1, 2], turnover = [1, 2, 3]),
        Check(
            late,
            [N.Supply.Raw, false, NutrientIntake.Blueprint],
            "Invalid size for parameter 's': expected (3,), got (2,).",
        )
    )

    @sysfails(
        base + N.Nodes(3) + NutrientIntake(2),
        Add(
            BroughtAlreadyInValue,
            N.Nodes,
            [N.Nodes.Number, false, NutrientIntake.Blueprint],
        )
    )

    @sysfails(
        base + N.Nodes(1) + NutrientIntake(nothing; turnover = [1, 2]),
        Check(
            late,
            [N.Turnover.Raw, false, NutrientIntake.Blueprint],
            "Invalid size for parameter 't': expected (1,), got (2,).",
        )
    )

end

end
