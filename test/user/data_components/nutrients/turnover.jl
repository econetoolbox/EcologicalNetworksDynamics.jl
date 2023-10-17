@testset "Nutrients turnover component." begin

    # Mostly duplicated from BodyMass.

    base = Model()

    #---------------------------------------------------------------------------------------
    # From raw values.

    # Vector.
    tr = Nutrients.Turnover([1, 2, 3])
    m = base + tr
    # Implies nutrients nodes.
    @test m.nutrients.richness == 3
    @test m.nutrients.names == [:n1, :n2, :n3]
    @test m.nutrients.turnover == [1, 2, 3]
    @test typeof(tr) == Nutrients.Turnover.Raw

    # Mapped input.
    ## Integer keys.
    tr = Nutrients.Turnover([2 => 1, 3 => 2, 1 => 3])
    m = base + tr
    @test m.nutrients.richness == 3
    @test m.nutrients.names == [:n1, :n2, :n3]
    @test m.nutrients.turnover == [3, 1, 2]
    @test typeof(tr) == Nutrients.Turnover.Map
    ## Symbol keys.
    tr = Nutrients.Turnover([:a => 1, :b => 2, :c => 3])
    m = base + tr
    @test m.nutrients.richness == 3
    @test m.nutrients.names == [:a, :b, :c]
    @test m.nutrients.turnover == [1, 2, 3]
    @test typeof(tr) == Nutrients.Turnover.Map

    # Editable property.
    m.nutrients.turnover[1] = 2
    m.nutrients.turnover[2:3] *= 10
    @test m.nutrients.turnover == [2, 20, 30]

    # Scalar (requires nodes to expand).
    tr = Nutrients.Turnover(2)
    m = base + Nutrients.Nodes(3) + tr
    @test m.nutrients.turnover == [2, 2, 2]
    @test typeof(tr) == Nutrients.Turnover.Flat
    @sysfails(
        Model(Nutrients.Turnover(5)),
        Missing(Nutrients.Nodes, Nutrients.Turnover, [Nutrients.Turnover.Flat], nothing)
    )

    # Checked.
    @sysfails(
        Model(Nutrients.Nodes(3)) + Nutrients.Turnover([1, 2]),
        Check(
            late,
            [Nutrients.Turnover.Raw],
            "Invalid size for parameter 't': expected (3,), got (2,).",
        )
    )

    #---------------------------------------------------------------------------------------
    # Input guards.

    @sysfails(
        Model(Nutrients.Turnover([1, -2])),
        Check(early, [Nutrients.Turnover.Raw], "Not a positive value: t[2] = -2.0.")
    )

    # Common ref checks from GraphDataInputs (not tested for every similar component).
    @sysfails(
        Model(Nutrients.Nodes(2)) + Nutrients.Turnover([1 => 0.1, 3 => 0.2]),
        Check(
            late,
            [Nutrients.Turnover.Map],
            "Invalid 'nutrient' node index in 't'. \
             Index does not fall within the valid range 1:2: [3] (0.2).",
        )
    )

    @sysfails(
        Model(Nutrients.Nodes(2)) + Nutrients.Turnover([:a => 0.1, :b => 0.2]),
        Check(
            late,
            [Nutrients.Turnover.Map],
            "Invalid 'nutrient' node label in 't'. \
             Expected either :n1 or :n2, got instead: [:a] (0.1).",
        )
    )

    @failswith(
        (m.nutrients.turnover[1] = 'a'),
        WriteError("not a value of type Real", :(nutrients.turnover), (1,), 'a')
    )

    @failswith(
        (m.nutrients.turnover[2:3] *= -10),
        WriteError(
            "Not a positive value: t[2] = -20.0.",
            :(nutrients.turnover),
            (2,),
            -20.0,
        )
    )

end
