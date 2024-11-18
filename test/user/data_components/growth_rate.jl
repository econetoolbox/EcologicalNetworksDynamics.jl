@testset "GrowthRate component." begin

    base = Model(Foodweb([:a => [:b, :c], :b => :c]))

    #---------------------------------------------------------------------------------------
    # From raw values.

    # Map selected species.
    for map in ([:c => 3], [3 => 3])
        gr = GrowthRate(map)
        m = base + gr
        @test m.growth_rate == [0, 0, 3] == m.r
        @test typeof(gr) == GrowthRate.Map
    end

    # From a sparse vector.
    gr = GrowthRate([0, 0, 4])
    m = base + gr
    @test m.growth_rate == [0, 0, 4] == m.r
    @test typeof(gr) == GrowthRate.Raw

    # From a single value.
    gr = GrowthRate(2)
    m = base + gr
    @test m.growth_rate == [0, 0, 2] == m.r
    @test typeof(gr) == GrowthRate.Flat

    #---------------------------------------------------------------------------------------
    # From allometric rates.

    base += BodyMass(; Z = 1) + MetabolicClass(:all_invertebrates)

    gr = GrowthRate(:Miele2019)
    @test gr.allometry[:p][:a] == 1
    @test gr.allometry[:p][:b] == -1 / 4
    @test typeof(gr) == GrowthRate.Allometric

    # Alternative explicit input.
    @test gr == GrowthRate.Allometric(; a_p = 1, b_p = -0.25)

    m = base + gr
    @test m.growth_rate == [0, 0, 1]

    #---------------------------------------------------------------------------------------
    # From temperature.

    gr = GrowthRate(:Binzer2016)
    @test gr.E_a == -0.84 # This one also has an activation energy.
    @test gr.allometry == Allometry(; p = (a = 1.5497531357028967e-7, b = -1 / 4))
    @test typeof(gr) == GrowthRate.Temperature

    # Alternative explicit input.
    @test gr == GrowthRate.Temperature(-0.84; p_a = 1.5497531357028967e-7, p_b = -1 / 4)

    m = base + Temperature(298.5) + gr
    @test m.growth_rate == [0, 0, 2.812547966878026e-7]

    @sysfails(base + gr, Missing(Temperature, nothing, [GrowthRate.Temperature], nothing))

    # ======================================================================================
    # Guards.

    #---------------------------------------------------------------------------------------
    # Raw values.

    @sysfails(
        base + GrowthRate([:a => 1]),
        Check(
            late,
            [GrowthRate.Map],
            "Invalid 'producer' node label in 'r': [:a] (1.0). \
             Valid nodes labels for this template are:\n  [:c]",
        )
    )

    @sysfails(
        base + GrowthRate([4, 5, 7]),
        Check(
            late,
            [GrowthRate.Raw],
            "Non-missing value found for 'r' at node index [1] (4.0), \
             but the template for 'producers' only allows values \
             at the following indices:\n  [3]",
        )
    )

    @sysfails(
        base + GrowthRate([0, -1, +1]),
        Check(early, [GrowthRate.Raw], "Not a positive value: r[2] = -1.0.")
    )

    @sysfails(
        base + GrowthRate(-1),
        Check(early, [GrowthRate.Flat], "Not a positive value: r = -1.0.")
    )

    @sysfails(
        base + GrowthRate([:a => 0, :b => -1, :c => 1]),
        Check(early, [GrowthRate.Map], "Not a positive value: r[:b] = -1.0.")
    )

    @sysfails(
        (base + GrowthRate([0, 0.5, 1])),
        Check(
            late,
            [GrowthRate.Raw],
            "Non-missing value found for 'r' at node index [2] (0.5), \
             but the template for 'producers' \
             only allows values at the following indices:\n  [3]",
        )
    )

    @sysfails(
        (base + GrowthRate([:a => 0.5])),
        Check(
            late,
            [GrowthRate.Map],
            "Invalid 'producer' node label in 'r': [:a] (0.5). \
             Valid nodes labels for this template are:\n  [:c]",
        )
    )

    #---------------------------------------------------------------------------------------
    # Allometry.

    # Forbid unnecessary allometric parameters.
    @sysfails(
        base + GrowthRate.Allometric(; p = (a = 1, b = 0.25), i = (a = 1, b = 0.25)),
        Check(
            early,
            [GrowthRate.Allometric],
            "Allometric rates for 'invertebrate' are meaningless in the context \
             of calculating growth rates: (a: 1.0, b: 0.25).",
        )
    )

    @sysfails(
        base + GrowthRate.Allometric(; p = (a = 1, b = 0.25, c = 8)),
        Check(
            early,
            [GrowthRate.Allometric],
            "Allometric parameter 'c' (target_exponent) for 'producer' \
             is meaningless in the context of calculating growth rates: 8.0.",
        )
    )

    @sysfails(
        base + GrowthRate.Allometric(; p = (a = 1, b = 0.25), i_a = 8),
        Check(
            early,
            [GrowthRate.Allometric],
            "Allometric rates for 'invertebrate' \
             are meaningless in the context of calculating growth rates: (a: 8.0).",
        )
    )

    # ======================================================================================
    # Edit guards.

    @viewfails(
        (m.growth_rate[1] = 2),
        EN.GrowthRates,
        "Invalid producer index [1] to write node data. \
         The only valid index for this template is 3.",
    )

    @failswith(
        (m.growth_rate[3] = -2),
        WriteError("Not a positive value: r[3] = -2.", :growth_rate, (3,), -2),
    )

end
