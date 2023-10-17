@testset "Consumption rate component." begin

    # Mostly duplicated from HalfSaturationDensity.

    base = Model(Foodweb([:a => :b, :b => :c]))

    #---------------------------------------------------------------------------------------
    # From raw values.

    # Map selected species.
    for map in ([:a => 1, :b => 2], [1 => 1, 2 => 2])
        cr = ConsumptionRate(map)
        m = base + cr
        @test m.consumption_rate == [1, 2, 0]
        @test typeof(cr) == ConsumptionRate.Map
    end

    # From a sparse vector.
    cr = ConsumptionRate([2, 4, 0])
    m = base + cr
    @test m.consumption_rate == [2, 4, 0]
    @test typeof(cr) == ConsumptionRate.Raw

    # From a single value.
    cr = ConsumptionRate(2)
    m = base + cr
    @test m.consumption_rate == [2, 2, 0]
    @test typeof(cr) == ConsumptionRate.Flat

    # ======================================================================================
    # Guards.

    #---------------------------------------------------------------------------------------
    # Raw values.

    @sysfails(
        base + ConsumptionRate([:c => 1]),
        Check(
            late,
            [ConsumptionRate.Map],
            "Invalid 'consumer' node label in 'alpha': [:c] (1.0). \
             Valid nodes labels for this template are:\n  [:a, :b]",
        )
    )

    @sysfails(
        base + ConsumptionRate([4, 5, 7]),
        Check(
            late,
            [ConsumptionRate.Raw],
            "Non-missing value found for 'alpha' at node index [3] (7.0), \
             but the template for 'consumers' only allows values \
             at the following indices:\n  [1, 2]",
        )
    )

    @sysfails(
        base + ConsumptionRate([0, -1, +1]),
        Check(early, [ConsumptionRate.Raw], "Not a positive value: alpha[2] = -1.0.")
    )

    @sysfails(
        base + ConsumptionRate(-1),
        Check(early, [ConsumptionRate.Flat], "Not a positive value: alpha = -1.0.")
    )

    @sysfails(
        base + ConsumptionRate([:a => 0, :b => -1, :c => 1]),
        Check(early, [ConsumptionRate.Map], "Not a positive value: alpha[:b] = -1.0.")
    )

    # ======================================================================================
    # Edit guards.

    @viewfails(
        (m.consumption_rate[3] = 2),
        EN.ConsumptionRates,
        "Invalid consumer index [3] to write node data. \
         Valid indices for this template are 1 and 2.",
    )

    @failswith(
        (m.consumption_rate[1] = -2),
        WriteError("Not a positive value: alpha[1] = -2.", :consumption_rate, (1,), -2),
    )

end
