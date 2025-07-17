module TestCarryingCapacity
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "Carrying capacity component." begin

    # Mostly duplicated from Growth.

    base = Model(Foodweb([:a => [:b, :c], :b => :c]))

    #---------------------------------------------------------------------------------------
    # From raw values.

    # Map selected species.
    for map in ([:c => 3], [3 => 3])
        cc = CarryingCapacity(map)
        m = base + cc
        @test m.carrying_capacity == [0, 0, 3] == m.K
        @test typeof(cc) == CarryingCapacity.Map
    end

    # From a sparse vector.
    cc = CarryingCapacity([0, 0, 4])
    m = base + cc
    @test m.carrying_capacity == [0, 0, 4] == m.K
    @test typeof(cc) == CarryingCapacity.Raw

    # From a single value.
    cc = CarryingCapacity(2)
    m = base + cc
    @test m.carrying_capacity == [0, 0, 2] == m.K
    @test typeof(cc) == CarryingCapacity.Flat

    #---------------------------------------------------------------------------------------
    # From temperature.

    base += BodyMass(; Z = 1) + MetabolicClass(:all_invertebrates)

    cc = CarryingCapacity(:Binzer2016)
    @test cc.E_a == 0.71
    @test cc.allometry == Allometry(; p = (a = 3.0, b = 0.28))
    @test typeof(cc) == CarryingCapacity.Temperature

    # Alternative explicit input.
    @test cc == CarryingCapacity.Temperature(0.71; p_a = 3.0, p_b = 0.28)

    m = base + Temperature(298.5) + cc
    @test m.carrying_capacity == [0, 0, 1.8127671052326149]

    @sysfails(
        base + cc,
        Missing(Temperature, nothing, [CarryingCapacity.Temperature], nothing)
    )

    # ======================================================================================
    # Guards.

    #---------------------------------------------------------------------------------------
    # Raw values.

    @sysfails(
        base + CarryingCapacity([:a => 1]),
        Check(
            late,
            [CarryingCapacity.Map],
            "Invalid 'producer' node label in 'K': [:a] (1.0). \
             Valid nodes labels for this template are:\n  [:c]",
        )
    )

    @sysfails(
        base + CarryingCapacity([4, 5, 7]),
        Check(
            late,
            [CarryingCapacity.Raw],
            "Non-missing value found for 'K' at node index [1] (4.0), \
             but the template for 'producers' only allows values \
             at the following indices:\n  [3]",
        )
    )

    @sysfails(
        base + CarryingCapacity([0, -1, +1]),
        Check(early, [CarryingCapacity.Raw], "Not a positive value: K[2] = -1.0.")
    )

    @sysfails(
        base + CarryingCapacity(-1),
        Check(early, [CarryingCapacity.Flat], "Not a positive value: K = -1.0.")
    )

    @sysfails(
        base + CarryingCapacity([:a => 0, :b => -1, :c => 1]),
        Check(early, [CarryingCapacity.Map], "Not a positive value: K[:b] = -1.0.")
    )

    #---------------------------------------------------------------------------------------
    # Allometry.

    base += Temperature(298.5)

    # Forbid unnecessary allometric parameters.
    @sysfails(
        base + CarryingCapacity.Temperature(0; p = (a = 1, b = 0.25, c = 8)),
        Check(
            early,
            [CarryingCapacity.Temperature],
            "Allometric parameter 'c' (target_exponent) for 'producer' \
             is meaningless in the context of calculating \
             carrying capacity (from temperature): 8.0.",
        )
    )

    @sysfails(
        base + CarryingCapacity.Temperature(0; p = (a = 1, b = 0.25), i_a = 8),
        Check(
            early,
            [CarryingCapacity.Temperature],
            "Allometric rates for 'invertebrate' \
             are meaningless in the context of calculating \
             carrying capacity (from temperature): (a: 8.0).",
        )
    )

    # ======================================================================================
    # Edit guards.

    @viewfails(
        (m.carrying_capacity[1] = 2),
        EN.CarryingCapacities,
        "Invalid producer index [1] to write node data. \
         The only valid index for this template is 3.",
    )

    @failswith(
        (m.carrying_capacity[3] = -2),
        WriteError("Not a positive value: K[3] = -2.", :carrying_capacity, (3,), -2),
    )

end

end
