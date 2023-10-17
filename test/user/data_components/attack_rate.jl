@testset "Attack rate component." begin

    # Mostly duplicated from HandlingTime.

    base = Model(Foodweb([:a => [:b, :c], :b => :c]))

    #---------------------------------------------------------------------------------------
    # Construct from raw values.

    # Matrix.
    ar = AttackRate([
        0 1 2
        0 0 3
        0 0 0
    ])
    m = base + ar
    @test m.attack_rate == [
        0 1 2
        0 0 3
        0 0 0
    ]
    @test typeof(ar) === AttackRate.Raw

    # Adjacency list.
    for adj in (
        #! format: off
        [:a => [:b => 1], :b => [:c => 3]],
        [1 => [2 => 1], 2 => [3 => 3]],
        #! format: on
    )
        ar = AttackRate(adj)
        m = base + ar
        @test m.attack_rate == [
            0 1 0
            0 0 3
            0 0 0
        ]
        @test typeof(ar) == AttackRate.Adjacency
    end

    # Scalar.
    ar = AttackRate(2)
    m = base + ar
    @test m.attack_rate == [
        0 2 2
        0 0 2
        0 0 0
    ]
    @test typeof(ar) == AttackRate.Flat

    #---------------------------------------------------------------------------------------
    # Construct from body masses.

    ar = AttackRate(:Miele2019)
    @sysfails(base + ar, Missing(BodyMass, nothing, [AttackRate.Miele2019], nothing))
    base += BodyMass(; Z = 1)
    m = base + ar
    @test m.attack_rate == [
        0 5 5
        0 0 5
        0 0 0
    ] * 10
    @test typeof(ar) == AttackRate.Miele2019

    #---------------------------------------------------------------------------------------
    # From temperature.

    ar = AttackRate(:Binzer2016)
    @test ar.E_a == -0.38
    @test ar.allometry[:i][:a] == exp(-13.1)
    @test ar.allometry[:e][:c] == -0.8
    @test typeof(ar) == AttackRate.Temperature

    @sysfails(base + ar, Missing(Temperature, nothing, [AttackRate.Temperature], nothing))
    base += Temperature(298.5)
    @sysfails(
        base + ar,
        Missing(MetabolicClass, nothing, [AttackRate.Temperature], nothing)
    )
    base += MetabolicClass(:all_invertebrates)
    m = base + ar
    a = 2.678153116108099e-6
    @test m.attack_rate == [
        0 a a
        0 0 a
        0 0 0
    ]

    #---------------------------------------------------------------------------------------
    # Imply foodweb.

    a_r = [
        1 2 0
        0 0 3
        0 0 0
    ]
    m = Model(AttackRate(a_r))
    @test has_component(m, Foodweb)
    @test m.species.names == [:s1, :s2, :s3]
    @test m.A == [
        1 1 0
        0 0 1
        0 0 0
    ]
    @test Model(Species([:a, :b, :c]), AttackRate(a_r)).species.names == [:a, :b, :c]
    # Imply species names via foodweb implication.
    @test Model(AttackRate([:a => [:a => 1, :b => 2], :b => [:c => 3]])).species.names ==
          [:a, :b, :c]
    @test Model(AttackRate([2 => [3 => 0.3], 1 => [1 => 0.1, 2 => 0.2]])).species.names ==
          [:s1, :s2, :s3]

    # ======================================================================================
    # Input guards.

    # Invalid values.
    @sysfails(
        base + AttackRate([
            0 1 -2
            3 0 4
            0 0 0
        ]),
        Check(early, [AttackRate.Raw], "Not a positive value: a_r[1, 3] = -2.0.")
    )

    @sysfails(
        base + AttackRate([:b => [:c => -5]]),
        Check(early, [AttackRate.Adjacency], "Not a positive value: a_r[:b, :c] = -5.0.")
    )

    @sysfails(
        base + AttackRate(-5),
        Check(early, [AttackRate.Flat], "Not a positive value: a_r = -5.0.")
    )

    # Respect template.
    @sysfails(
        base + AttackRate([
            0 1 2
            3 0 4
            0 0 0
        ]),
        Check(
            late,
            [AttackRate.Raw],
            "Non-missing value found for 'a_r' at edge index [2, 1] (3.0), \
             but the template for 'trophic links' only allows values \
             at the following indices:\n  [(1, 2), (1, 3), (2, 3)]",
        )
    )

    @sysfails(
        base + AttackRate([:b => [:a => 5]]),
        Check(
            late,
            [AttackRate.Adjacency],
            "Invalid 'trophic link' edge label in 'a_r': [:b, :a] (5.0). \
             Valid edges target labels for source [:b] in this template are:\n  [:c]",
        )
    )

end
