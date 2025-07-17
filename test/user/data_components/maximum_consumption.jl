module TestMaximumConsumption
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "MaximumConsumption component." begin

    # Mostly duplicated from CarryingCapacity.

    base = Model(Foodweb([:a => :b, :b => :c]))

    #---------------------------------------------------------------------------------------
    # From raw values.

    # Map selected species.
    for map in ([:a => 1, :b => 2], [1 => 1, 2 => 2])
        mc = MaximumConsumption(map)
        m = base + mc
        @test m.maximum_consumption == [1, 2, 0] == m.y
        @test typeof(mc) == MaximumConsumption.Map
    end

    # From a sparse vector.
    mc = MaximumConsumption([2, 4, 0])
    m = base + mc
    @test m.maximum_consumption == [2, 4, 0] == m.y
    @test typeof(mc) == MaximumConsumption.Raw

    # From a single value.
    mc = MaximumConsumption(2)
    m = base + mc
    @test m.maximum_consumption == [2, 2, 0] == m.y
    @test typeof(mc) == MaximumConsumption.Flat

    #---------------------------------------------------------------------------------------
    # From allometric rates.

    base += BodyMass(1.2) + MetabolicClass(:all_ectotherms)

    mc = MaximumConsumption(:Miele2019)
    @test mc.allometry[:i][:a] == 8
    @test mc.allometry[:i][:b] == 0
    m = base + mc
    @test m.maximum_consumption == [4, 4, 0]
    @test typeof(mc) == MaximumConsumption.Allometric

    # ======================================================================================
    # Guards.

    #---------------------------------------------------------------------------------------
    # Raw values.

    @sysfails(
        base + MaximumConsumption([:c => 1]),
        Check(
            late,
            [MaximumConsumption.Map],
            "Invalid 'consumer' node label in 'y': [:c] (1.0). \
             Valid nodes labels for this template are:\n  [:a, :b]",
        )
    )

    @sysfails(
        base + MaximumConsumption([4, 5, 7]),
        Check(
            late,
            [MaximumConsumption.Raw],
            "Non-missing value found for 'y' at node index [3] (7.0), \
             but the template for 'consumers' only allows values \
             at the following indices:\n  [1, 2]",
        )
    )

    @sysfails(
        base + MaximumConsumption([0, -1, +1]),
        Check(early, [MaximumConsumption.Raw], "Not a positive value: y[2] = -1.0.")
    )

    @sysfails(
        base + MaximumConsumption(-1),
        Check(early, [MaximumConsumption.Flat], "Not a positive value: y = -1.0.")
    )

    @sysfails(
        base + MaximumConsumption([:a => 0, :b => -1, :c => 1]),
        Check(early, [MaximumConsumption.Map], "Not a positive value: y[:b] = -1.0.")
    )

    #---------------------------------------------------------------------------------------
    # Allometry.

    # Forbid unnecessary allometric parameters.
    @sysfails(
        base + MaximumConsumption.Allometric(; p = (a = 1, b = 0.25)),
        Check(
            early,
            [MaximumConsumption.Allometric],
            "Allometric rates for 'producer' are meaningless in the context \
             of calculating maximum consumption rates: (a: 1.0, b: 0.25).",
        )
    )

    @sysfails(
        base + MaximumConsumption.Allometric(; i = (a = 1, b = 0.25, c = 8)),
        Check(
            early,
            [MaximumConsumption.Allometric],
            "Allometric parameter 'c' (target_exponent) for 'invertebrate' \
             is meaningless in the context of calculating maximum consumption rates: 8.0.",
        )
    )

    @sysfails(
        base + MaximumConsumption.Allometric(; e = (a = 1, b = 0.25), i_a = 8),
        Check(
            early,
            [MaximumConsumption.Allometric],
            "Missing allometric parameter 'b' (source_exponent) for 'invertebrate', \
             required to calculate maximum consumption rates.",
        )
    )

    # ======================================================================================
    # Edit guards.

    @viewfails(
        (m.maximum_consumption[3] = 2),
        EN.MaximumConsumptionRates,
        "Invalid consumer index [3] to write node data. \
         Valid indices for this template are 1 and 2.",
    )

    @failswith(
        (m.maximum_consumption[1] = -2),
        WriteError("Not a positive value: y[1] = -2.", :maximum_consumption, (1,), -2),
    )

end

end
