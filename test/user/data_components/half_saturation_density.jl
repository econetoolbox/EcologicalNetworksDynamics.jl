module TestHalfSaturationDensity
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "Half-saturation density component." begin

    # Mostly duplicated from MaximumConsumption.

    base = Model(Foodweb([:a => :b, :b => :c]))

    #---------------------------------------------------------------------------------------
    # From raw values.

    # Map selected species.
    for map in ([:a => 1, :b => 2], [1 => 1, 2 => 2])
        hd = HalfSaturationDensity(map)
        m = base + hd
        @test m.half_saturation_density == [1, 2, 0]
        @test typeof(hd) == HalfSaturationDensity.Map
    end

    # From a sparse vector.
    hd = HalfSaturationDensity([2, 4, 0])
    m = base + hd
    @test m.half_saturation_density == [2, 4, 0]
    @test typeof(hd) == HalfSaturationDensity.Raw

    # From a single value.
    hd = HalfSaturationDensity(2)
    m = base + hd
    @test m.half_saturation_density == [2, 2, 0]
    @test typeof(hd) == HalfSaturationDensity.Flat

    # ======================================================================================
    # Guards.

    #---------------------------------------------------------------------------------------
    # Raw values.

    @sysfails(
        base + HalfSaturationDensity([:c => 1]),
        Check(
            late,
            [HalfSaturationDensity.Map],
            "Invalid 'consumer' node label in 'B0': [:c] (1.0). \
             Valid nodes labels for this template are:\n  [:a, :b]",
        )
    )

    @sysfails(
        base + HalfSaturationDensity([4, 5, 7]),
        Check(
            late,
            [HalfSaturationDensity.Raw],
            "Non-missing value found for 'B0' at node index [3] (7.0), \
             but the template for 'consumers' only allows values \
             at the following indices:\n  [1, 2]",
        )
    )

    @sysfails(
        base + HalfSaturationDensity([0, -1, +1]),
        Check(early, [HalfSaturationDensity.Raw], "Not a positive value: B0[2] = -1.0.")
    )

    @sysfails(
        base + HalfSaturationDensity(-1),
        Check(early, [HalfSaturationDensity.Flat], "Not a positive value: B0 = -1.0.")
    )

    @sysfails(
        base + HalfSaturationDensity([:a => 0, :b => -1, :c => 1]),
        Check(early, [HalfSaturationDensity.Map], "Not a positive value: B0[:b] = -1.0.")
    )

    # ======================================================================================
    # Edit guards.

    @viewfails(
        (m.half_saturation_density[3] = 2),
        EN.HalfSaturationDensities,
        "Invalid consumer index [3] to write node data. \
         Valid indices for this template are 1 and 2.",
    )

    @failswith(
        (m.half_saturation_density[1] = -2),
        WriteError("Not a positive value: B0[1] = -2.", :half_saturation_density, (1,), -2),
    )

end

end
