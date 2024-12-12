@testset "Nutrient intake component." begin

    const N = Nutrients

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

    # Watch consistency.
    @sysfails(
        base + NutrientIntake(; supply = [1, 2]), #  HERE: fix with standard 'PerProducer'.
        Check(NutrientIntake, N.SupplyFromRawValues),
        "Invalid size for parameter 's': expected (3,), got (2,)."
    )
    @sysfails(
        base + Nutrients.Nodes(3) + NutrientIntake(2),
        Check(NutrientIntake),
        "blueprint also brings '$(Nutrients.Nodes)', which is already in the system."
    )
    @sysfails(
        base + Nutrients.Nodes(1) + NutrientIntake(nothing; turnover = [1, 2]),
        Check(NutrientIntake, Nutrients.TurnoverFromRawValues),
        "Invalid size for parameter 't': expected (1,), got (2,)."
    )
    @sysfails(
        base + NutrientIntake(3; turnover = [1, 2]),
        Check(NutrientIntake, Nutrients.TurnoverFromRawValues),
        "Invalid size for parameter 't': expected (3,), got (2,)."
    )
    @argfails(
        NutrientIntake(3; nodes = 2),
        "Nodes specified once as plain argument (3) and once as keyword argument (nodes = 2)."
    )

end
